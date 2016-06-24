function getline(s::TCPSocket)
    l = chomp(readline(s))
    length(l) > 1 || throw(ProtocolException("Invalid response received: $l"))
    return l
end

function parse_simple_string(l::AbstractString)
    return l
end

function parse_error(l::AbstractString)
    println(l)
    throw(ServerException(l))
end

function parse_integer(l)
    return parse(Int, l)
end

function parse_bulk_string(s::TCPSocket, len::Int)
    b = read(s, UInt8, len+2) # add crlf
    if length(b) != len + 2
        throw(ProtocolException(
            "Bulk string read error: expected $len bytes; received $(length(b))"
        ))
    else
        return join(map(Char,b[1:end-2]))
    end
end

function parse_integer(l::AbstractString)
    return parse(Int, l)
end

function parse_array(s::TCPSocket, n::Int)
    a = []
    for i = 1:n
        l = getline(s)
        r = parseline(l, s)
        push!(a, r)
    end
    return a
end

function parseline(l::AbstractString, s::TCPSocket)
    reply_type = l[1]
    reply_token = l[2:end]
    if reply_type == '+'
        parse_simple_string(reply_token)
    elseif reply_type == '-'
        parse_error(reply_token)
    elseif reply_type == ':'
        parse_integer(reply_token)
    elseif reply_type == '$'
        len = parse_integer(reply_token)
        if len == -1
            return nothing
        else
            parse_bulk_string(s, len)
        end
    elseif reply_type == '*'
        len = parse_integer(reply_token)
        if len == -1
            return nothing
        else
            parse_array(s, len)
        end
    end
end

"""
Formatting of outgoing commands to the Redis server

merl-dev:  added check for Float token. `length(x::Float)==1` causing command
to fail.  `length(string(token))` returns the appropriate length for Redis.
"""
function pack_command(command)
    packed_command = "*$(length(command))\r\n"
    for token in command
        ltoken = ifelse(typeof(token) <: Number, length(string(token)), length(token))
        packed_command = string(packed_command, "\$$(ltoken)\r\n", token, "\r\n")
    end
    packed_command
end

function execute_command_without_reply(conn::RedisConnectionBase, command)
    is_connected(conn) || throw(ConnectionException("Socket is disconnected"))
    send_command(conn, pack_command(command))
end

function read_reply(conn::RedisConnectionBase)
    l = getline(conn.socket)
    reply = parseline(l, conn.socket)
    return reply
end

function execute_command(conn::RedisConnectionBase, command)
    execute_command_without_reply(conn, command)
    read_reply(conn)
end

baremodule SubscriptionMessageType
    const Message = 0
    const Pmessage = 1
    const Other = 2
end

immutable SubscriptionMessage
    message_type
    channel::AbstractString
    message::AbstractString

    function SubscriptionMessage(reply::AbstractArray)
        notification = reply
        message_type = notification[1]
        if message_type == "message"
            new(SubscriptionMessageType.Message, notification[2], notification[3])
        elseif message_type == "pmessage"
            new(SubscriptionMessageType.Pmessage, notification[2], notification[4])
        else
            new(SubscriptionMessageType.Other, "", "")
        end
    end
end
