import DataStructures.OrderedSet

flatten(token) = string(token)
flatten(token::Vector{UInt8}) = [token]
flatten(token::String) = token
flatten(token::Array) = map(string, token)
flatten(token::Set) = map(string, collect(token))

# the following doesn't work in Julia v0.5
# flatten(token::Dict) = map(string, vcat(map(collect, token)...))
function flatten(token::Dict)
    r=Union{String, Vector{UInt8}}[]
    for (k,v) in token
        push!(r, flatten(k))
        push!(r, flatten(v))
    end
    r
end

function flatten(token::Tuple{T, U}...) where {T <: Number, U <: AbstractString}
    r=[]
    for item in token
        push!(r, item[1])
        push!(r, item[2])
    end
    r
end

flatten_command(command...) = vcat(map(flatten, command)...)

######## Type Conversions #########

convert_response(::Type{Float64}, response::T) where {T <: AbstractString} = parse(Float64, response)::Float64
convert_response(::Type{Float64}, response::T) where {T <: Real} = float(response)::Float64
convert_response(::Type{Bool}, response::AbstractString) = response == "OK" || response == "QUEUED" ? true : false
convert_response(::Type{Bool}, response::Integer) = response == 1 ? true : false
convert_response(::Type{Set{AbstractString}}, response::Array) = Set{AbstractString}(String(r) for r in response)
convert_response(::Type{OrderedSet{AbstractString}}, response) = OrderedSet{AbstractString}(String(r) for r in response)

function convert_response(::Type{Dict{AbstractString, AbstractString}}, response)
    iseven(length(response)) || throw(ClientException("Response could not be converted to Dict"))
    retdict = Dict{AbstractString, AbstractString}()
    for i=1:2:length(response)
        retdict[String(response[i])] = String(response[i+1])
    end
    retdict
end

function convert_eval_response(::Any, response::Array)
    return [String(r) for r in response]
end
function convert_eval_response(::Any, response)
    return String(response)
end

# import Base: ==
# ==(A::Union{T, Nothing}, B::Union{U, Nothing}) where {T<:AbstractString, U<:AbstractString} = A == B
# ==(A::Union{T, Nothing}, B::Union{U, Nothing}) where {T<:Number, U<:Number} = A == B

convert_response(::Type{AbstractString}, response) = string(response)
convert_response(::Type{Integer}, response) = response

function convert_response(::Type{Array{AbstractString, 1}}, response)
    r = Array{AbstractString, 1}()
    for item in response
        push!(r, String(item))
    end
    r
end

function convert_response(::Type{Tuple{Integer,Array{AbstractString,1}}}, response)
    cursor = parse(Int, response[1])
    r = Array{AbstractString, 1}()
    for item in response[2]
        push!(r, convert(String, item))
    end
    (cursor, r)
end

function convert_response(::Type{Tuple{Integer,Dict{AbstractString,AbstractString}}}, response::Array{Any,1})
    cursor = parse(Int, response[1])
    return (cursor, convert_response(Dict{AbstractString, AbstractString}, response[2]))
end

function convert_response(::Type{Union{T, Nothing}}, response) where {T<:Number}
    return response
end

function convert_response(::Type{Union{T, Nothing}}, response) where {T <: AbstractString}
    return response
end

# redundant
function convert_response(::Type{Array{Union{T, Nothing}, 1}}, response) where {T<:Number}
    if response == nothing
        Array{Union{T, Nothing}, 1}()
   else
        r = Array{Union{T, Nothing}, 1}()
        for item in response
            push!(r, tryparse(T, item))
        end
        r
    end
end

function convert_response(::Type{Array{Union{T, Nothing}, 1}}, response) where {T <: AbstractString}
    if response == nothing
        Array{Union{T, Nothing}, 1}()
   else
        r = Array{Union{T, Nothing}, 1}()
        for item in response
            if item !== nothing
                item = String(item)
            end
            push!(r, item)
        end
        r
    end
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

nullcb(err) = @debug err
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
            reply = convert_reply(reply)
            message = SubscriptionMessage(reply)
            if message.message_type == SubscriptionMessageType.Message
                conn.callbacks[message.channel](message.message)
            elseif message.message_type == SubscriptionMessageType.Pmessage
                conn.pcallbacks[message.channel](message.message)
            elseif message.message_type == SubscriptionMessageType.Unsubscribe
                delete!(conn.callbacks, message.channel)
            end
        catch err
            err_callback(err)
        end
    end
end

macro redisfunction(command::AbstractString, ret_type, args...)
    is_exec = Symbol(command) == :exec
    func_name = esc(Symbol(command))
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
            function $(func_name)(conn::SubscriptionConnection, $(args...))
                execute_command_without_reply(conn, flatten_command($(command...), $(args...)))
            end
        end
    else
        q1 = quote
            function $(func_name)(conn::RedisConnection)
                response = execute_command(conn, flatten_command($(command...)))
                convert_response($ret_type, response)
            end
        end
        q2 = quote
            function $(func_name)(conn::TransactionConnection)
                execute_command(conn, flatten_command($(command...)))
            end
        end
        q3 = quote
            function $(func_name)(conn::PipelineConnection)
                execute_command_without_reply(conn, flatten_command($(command...)))
                conn.num_commands += 1
            end
        end
        # To avoid redefining `function exec(conn::TransactionConnection)`
        if is_exec
            return Expr(:block, q1.args[2], q3.args[2])
        else
            return Expr(:block, q1.args[2], q2.args[2], q3.args[2])
        end
    end
end

macro sentinelfunction(command, ret_type, args...)
    func_name = esc(Symbol(string("sentinel_", command)))
    return quote
        function $(func_name)(conn::SentinelConnection, $(args...))
            response = execute_command(conn, flatten_command("sentinel", $command, $(args...)))
            convert_response($ret_type, response)
        end
    end
end
