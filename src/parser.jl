"""
Formatting of incoming Redis Replies
"""
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
