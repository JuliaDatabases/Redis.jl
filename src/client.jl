import DataStructures.OrderedSet

flatten(token) = string(token)
flatten(token::AbstractString) = token
flatten(token::Array) = map(string, token)
flatten(token::Set) = map(string, collect(token))
flatten(token::Dict) = map(string, vcat(map(collect, token)...))

flatten_command(command...) = vcat(map(flatten, command)...)

convert_response(::Any, response) = response
convert_response(::Type{Float64}, response) = float(response)::Float64
convert_response(::Type{Bool}, response::AbstractString) = response == "OK" || response == "QUEUED" ? true : false
convert_response(::Type{Bool}, response::Integer) = convert(Bool, response)
convert_response(::Type{Set}, response) = Set(response)
convert_response(::Type{OrderedSet}, response) = OrderedSet(response)
function convert_response(::Type{Dict}, response)
    iseven(length(response)) || throw(ClientException("Response could not be converted to Dict"))
    retdict = Dict{AbstractString, AbstractString}()
    for i=1:2:length(response)
        retdict[response[i]] = response[i+1]
    end
    retdict
end

function open_transaction(conn::RedisConnection)
    t = TransactionConnection(conn)
    multi(t)
    t
end

function reset_transaction(conn::TransactionConnection)
    discard(conn)
    multi(conn)
end

function open_pipeline(conn::RedisConnection)
    PipelineConnection(conn)
end

function read_pipeline(conn::PipelineConnection)
    result = Any[]
    for i=1:conn.num_commands
        push!(result, read_reply(conn))
    end
    conn.num_commands = 0
    result
end

nullcb(err) = nothing
function open_subscription(conn::RedisConnection, err_callback=nullcb)
    s = SubscriptionConnection(conn)
    @async subscription_loop(s, err_callback)
    s
end

function subscription_loop(conn::SubscriptionConnection, err_callback::Function)
    while is_connected(conn)
        try
            l = getline(conn.socket)
            reply = parseline(l, conn.socket)
            message = SubscriptionMessage(reply)
            if message.message_type == SubscriptionMessageType.Message
                conn.callbacks[message.channel](message.message)
            elseif message.message_type == SubscriptionMessageType.Pmessage
                conn.pcallbacks[message.channel](message.message)
            end
        catch err
            err_callback(err)
        end
    end
end

macro redisfunction(command, ret_type, args...)
    func_name = esc(symbol(command))
    command = lstrip(command,'_')
    command = split(command, '_')


    if length(args) > 0
        return quote
            function $(func_name)(conn::RedisConnection, $(args...))
                response = execute_command(conn, flatten_command($(command...), $(args...)))
                convert_response($ret_type, response)
            end
            function $(func_name)(conn::TransactionConnection, $(args...))
                execute_command(conn, flatten_command($(command...), $(args...)))
            end
            function $(func_name)(conn::PipelineConnection, $(args...))
                execute_command_without_reply(conn, flatten_command($(command...), $(args...)))
                conn.num_commands += 1
            end
        end
    else
        return quote
            function $(func_name)(conn::RedisConnection)
                response = execute_command(conn, flatten_command($(command...)))
                convert_response($ret_type, response)
            end
            function $(func_name)(conn::TransactionConnection)
                execute_command(conn, flatten_command($(command...)))
            end
            function $(func_name)(conn::PipelineConnection)
                execute_command_without_reply(conn, flatten_command($(command...)))
                conn.num_commands += 1
            end
        end
    end
end

macro sentinelfunction(command, ret_type, args...)
    func_name = esc(symbol(string("sentinel_", command)))
    return quote
        function $(func_name)(conn::SentinelConnection, $(args...))
            response = execute_command(conn, flatten_command("sentinel", $command, $(args...)))
            convert_response($ret_type, response)
        end
    end
end
