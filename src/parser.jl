const CRLF = "\r\n"

immutable ParsedReply
    response # The type of the response is determined by the server (Int, String, Array)
    reply_length::Integer
end

function parse_reply(reply)
    first_crlf = search(reply, CRLF)
    length(reply) >= 3   || throw(ProtocolException(reply))
    first_crlf.start > 0 || throw(ProtocolException(reply))
    reply_type = reply[1]
    if reply_type == '+'
        parse_simple_string_reply(reply, first_crlf)
    elseif reply_type == '-'
        parse_error_reply(reply, first_crlf)
    elseif reply_type == ':'
        parse_integer_reply(reply, first_crlf)
    elseif reply_type == '\$'
        parse_bulk_reply(reply, first_crlf)
    elseif reply_type == '*'
        parse_array_reply(reply, first_crlf)
    else
        throw(ProtocolException(reply))
    end
end

# Simple strings replys extend to the first encountered CRLF
function parse_simple_string_reply(reply, first_crlf)
    ParsedReply(reply[2:first_crlf.start-1], first_crlf.stop)
end

# Errors are the same as simple strings, except that their first token specifies
# the error type
function parse_error_reply(reply, first_crlf)
    first_space = search(reply, ' ')
    first_space > 0 || throw(ProtocolException(reply))
    throw(ServerException(reply[2:first_space-1], reply[first_space+1:first_crlf.start-1]))
end

# Integer replies are just ints followed by CRLF
function parse_integer_reply(reply, first_crlf)
    try
        ParsedReply(parse(Int, reply[2:first_crlf.start-1]), first_crlf.stop)
    catch
        throw(ProtocolException(reply))
    end
end

# Bulk replies specify their length and then the binary-safe string
function parse_bulk_reply(reply, first_crlf)
    try
        bulk_length = parse(Int, reply[2:first_crlf.start-1])
        bulk_length == -1 && return ParsedReply(nothing, first_crlf.stop)
        reply_end = first_crlf.stop+bulk_length
        ParsedReply(reply[first_crlf.stop+1:reply_end], reply_end+2)
    catch
        throw(ProtocolException(reply))
    end
end

# Array replies specify the number of elements and then other reply types
# for each item in length
function parse_array_reply(reply, first_crlf)
    try
        array_length = parse(Int, reply[2:first_crlf.start-1])
        array_length == -1 && return ParsedReply(nothing, first_crlf.stop)
        reply = reply[first_crlf.stop+1:end]
        reply_length = first_crlf.stop
        response = Any[]
        for i=1:array_length
            parsed_element = parse_reply(reply)
            push!(response, parsed_element.response)
            reply_length += parsed_element.reply_length
            reply = reply[parsed_element.reply_length+1:end]
        end
        ParsedReply(response, reply_length)
    catch
        throw(ProtocolException(reply))
    end
end

# Formatting of outgoing commands to the Redis server
function pack_command(command)
    packed_command = "*$(length(command))\r\n"
    for token in command
        packed_command = string(packed_command, "\$$(length(token))\r\n", token, "\r\n")
    end
    packed_command
end

baremodule SubscriptionMessageType
    const Message = 0
    const Pmessage = 1
    const Other = 2
end

immutable SubscriptionMessage
    message_type
    channel::String
    message::String

    function SubscriptionMessage(reply)
        notification = reply.response
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
