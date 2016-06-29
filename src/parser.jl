"""
Formatting of incoming Redis Replies
"""
function getline(s::TCPSocket)
    l = chomp(readline(s))
    length(l) > 1 || throw(ProtocolException("Invalid response received: $l"))
    return l
end

function read_reply(conn::RedisConnectionBase)
    l = getline(conn.socket)
    reply = parseline(l, conn.socket)
    return reply
end

parse_error(l::AbstractString) = throw(ServerException(l))

function parse_bulk_string(s::TCPSocket, slen::Int)
    b = read(s, UInt8, slen+2) # add crlf
    if length(b) != slen + 2
        throw(ProtocolException(
            "Bulk string read error: expected $len bytes; received $(length(b))"
        ))
    else
        return bytestring(b[1:end-2])
    end
end

function parse_array(s::TCPSocket, slen::Int)
    a = Array{Any, 1}(slen)
    for i = 1:slen
        l = getline(s)
        r = parseline(l, s)
        a[i] = r
    end
    return a
end

function parseline(l::AbstractString, s::TCPSocket)
    reply_type = l[1]
    reply_token = l[2:end]
    if reply_type == '+'
        return reply_token
    elseif reply_type == ':'
        parse(Int, reply_token)
    elseif reply_type == '$'
        slen = parse(Int, reply_token)
        if slen == -1
            Nullable{AbstractString}()
        else
            parse_bulk_string(s, slen)
        end
    elseif reply_type == '*'
        slen = parse(Int, reply_token)
        if slen == -1
            Nullable{AbstractString}()
        else
            parse_array(s, slen)
        end
    elseif reply_type == '-'
        parse_error(reply_token)
    end
end



"""
Formatting of outgoing commands to the Redis server
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
