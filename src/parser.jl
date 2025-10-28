"""
Formatting of incoming Redis Replies
"""

include("connection.jl")

function getline(t::Transport.RedisTransport)
    l = chomp(Transport.read_line(t))
    length(l) > 1 || throw(ProtocolException("Invalid response received: $l"))
    return l
end

convert_reply(reply::Array{UInt8}) = String(reply)
convert_reply(reply::Array) = [convert_reply(r) for r in reply]
convert_reply(x) = x

function read_reply(conn::RedisConnectionBase)
    l = getline(conn.transport)
    reply = parseline(l, conn.transport)
    convert_reply(reply)
end

parse_error(l::AbstractString) = throw(ServerException(l))

function parse_bulk_string(t::Transport.RedisTransport, slen::Int)
    b = Transport.read_nbytes(t, slen+2) # add crlf
    if length(b) != slen + 2
        throw(ProtocolException(
            "Bulk string read error: expected $slen bytes; received $(length(b))"
        ))
    else
        return resize!(b, slen)
    end
end

function parse_array(t::Transport.RedisTransport, slen::Int)
    a = Array{Any, 1}(undef, slen)
    for i = 1:slen
        l = getline(t)
        r = parseline(l, t)
        a[i] = r
    end
    return a
end

function parseline(l::AbstractString, t::Transport.RedisTransport)
    reply_type = l[1]
    reply_token = l[2:end]
    if reply_type == '+'
        return reply_token
    elseif reply_type == ':'
        parse(Int, reply_token)
    elseif reply_type == '$'
        slen = parse(Int, reply_token)
        if slen == -1
            nothing
        else
            parse_bulk_string(t, slen)
        end
    elseif reply_type == '*'
        slen = parse(Int, reply_token)
        if slen == -1
            nothing
        else
            parse_array(t, slen)
        end
    elseif reply_type == '-'
        parse_error(reply_token)
    end
end

write_token(io::IO, token::Union{AbstractString, Vector{UInt8}}) =
  write(io, "\$", string(sizeof(token)), "\r\n", token, "\r\n")

function write_token(io::IO, token)
  s = string(token)
  write(io, "\$", string(sizeof(s)), "\r\n", s, "\r\n")
end

"""
Formatting of outgoing commands to the Redis server
"""
function pack_command(io::IO, command::Vector)
    b = write(io, "*$(length(command))\r\n")

    for token in command
        b += write_token(io, token)
    end
    b
end

function execute_command_without_reply(conn::RedisConnectionBase, command)
    is_connected(conn) || throw(ConnectionException("Socket is disconnected"))
    iob = IOBuffer()
    pack_command(iob, command)
    Transport.io_lock(conn.transport) do
        Transport.write_bytes(conn.transport, take!(iob))
    end
end

function execute_command(conn::RedisConnectionBase, command::Vector)
    execute_command_without_reply(conn, command)
    read_reply(conn)
end

# execute_command for RedisClusterConnection
function execute_command(cluster::RedisClusterConnection, command::Vector)
    # For cluster connections, need to find the corresponding node based on the key in the command
    # Most Redis commands have the key as the first argument
    max_redirects = 5
    redirects = 0

    while redirects < max_redirects
        try
            # Try to extract key from command and get corresponding connection
            local target_conn

            if length(command) >= 2
                # Most command format: [CMD, KEY, ...]
                # But some commands have different structure
                cmd_name = uppercase(string(command[1]))

                # Commands where key is at position 3 instead of 2
                # BITOP operation destkey key [key ...]
                key_index = if cmd_name == "BITOP" && length(command) >= 3
                    3  # destkey position
                else
                    2  # default key position
                end

                key = command[key_index]
                target_conn = get_connection_for_key(cluster, string(key))
            else
                # For commands without keys (like PING), use any connection
                if !isempty(cluster.node_connections)
                    target_conn = first(values(cluster.node_connections))
                else
                    throw(ConnectionException("No active connections in cluster"))
                end
            end

            # Execute command on target connection
            execute_command_without_reply(target_conn, command)
            return read_reply(target_conn)

        catch e
            if isa(e, ServerException)
                # Handle MOVED redirect
                if occursin("MOVED", e.message)
                    redirects += 1
                    @info "Cluster redirect: $(e.message) (attempt $redirects/$max_redirects)"

                    # Parse MOVED response: "MOVED slot host:port"
                    parts = split(e.message, " ")
                    if length(parts) >= 3
                        slot = parse(UInt16, parts[2])
                        connect_info_string = parts[3]
                        connect_info = split(connect_info_string, ":")

                        if length(connect_info) >= 2
                            host = String(connect_info[1])
                            port = parse(Int, connect_info[2])

                            # Get or create connection to new node and update slot mapping
                            new_conn = get_node_connection(cluster, host, port)
                            cluster.slot_map[slot] = new_conn

                            # Retry command (via while loop)
                            continue
                        end
                    end

                    # If parsing failed, refresh entire slot map
                    @warn "Failed to parse MOVED response, refreshing entire slot map"
                    refresh_slot_map!(cluster)
                    continue

                    # Handle ASK redirect
                elseif occursin("ASK", e.message)
                    redirects += 1
                    @info "Cluster ASK redirect: $(e.message) (attempt $redirects/$max_redirects)"

                    # Parse ASK response: "ASK slot host:port"
                    parts = split(e.message, " ")
                    if length(parts) >= 3
                        connect_info_string = parts[3]
                        connect_info = split(connect_info_string, ":")

                        if length(connect_info) >= 2
                            host = String(connect_info[1])
                            port = parse(Int, connect_info[2])

                            # ASK requires sending ASKING command first, then retry original command
                            ask_conn = get_node_connection(cluster, host, port)
                            execute_command(ask_conn, ["ASKING"])
                            execute_command_without_reply(ask_conn, command)
                            return read_reply(ask_conn)
                        end
                    end

                    @warn "Failed to parse ASK response: $(e.message)"
                    rethrow(e)
                end
            end

            # Rethrow other errors
            rethrow(e)
        end
    end

    throw(ConnectionException("Too many cluster redirects ($max_redirects)"))
end

baremodule SubscriptionMessageType
    const Message = 0
    const Pmessage = 1
    const Other = 2
end

struct SubscriptionMessage
    message_type
    channel::AbstractString
    key::Union{AbstractString,Nothing}
    message::AbstractString

    function SubscriptionMessage(reply::AbstractArray)
        message_type = reply[1]
        if message_type == "message"
            new(SubscriptionMessageType.Message, reply[2], nothing, reply[3])
        elseif message_type == "pmessage"
            new(SubscriptionMessageType.Pmessage, reply[2], reply[3], reply[4])
        else
            new(SubscriptionMessageType.Other, "", "")
        end
    end
end
