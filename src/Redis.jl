module Redis

using AwsIO, Logging, Base64, StringViews, Parsers
include("commands.jl")
using .Commands

struct RedisError <: Exception
    msg::String
end
Base.showerror(io::IO, e::RedisError) = print(io, e.msg)

struct Response
    value::Any
    error::Union{Nothing,Exception}
end

mutable struct Client
    socket::AwsIO.Sockets.Client
    repsonse_buffer::Vector{UInt8}
    debug::Bool
    responses::Channel{Response}
    reader_task::Task
end

Client(socket::AwsIO.Sockets.Client, buf::Vector{UInt8}, debug::Bool) = Client(socket, buf, debug, Channel{Response}(Inf), Task(nothing))

function connect(host::String, port::Integer=6379; password::Union{String, Nothing}=nothing, db::Integer=0, tls::Bool=false, debug::Bool=false, buffer_capacity::Int=AwsIO.Sockets.DEFAULT_READ_BUFFER_SIZE, socketdebug::Bool=false)
    socket = AwsIO.Sockets.Client(host, port; tls=tls, debug=socketdebug)
    response_buffer = Vector{UInt8}(undef, 4096)
    client = Client(socket, response_buffer, debug)
    start_response_reader!(client)
    if password !== nothing
        command = "*2\r\n\$4\r\nAUTH\r\n\$$(length(password))\r\n$password\r\n"
        resp = execute(client, command)
        debug && @info "AUTH sent: $resp"
    end
    if db > 0
        command = "*2\r\n\$6\r\nSELECT\r\n\$$(length(string(db)))\r\n$db\r\n"
        resp = execute(client, command)
        debug && @info "SELECT sent: $resp"
    end
    return client
end

function Base.close(client::Client)
    close(client.socket)
    return
end

Base.isopen(client::Client) = isopen(client.socket)

function start_response_reader!(client::Client)
    client.responses = Channel{Response}(Inf)
    client.reader_task = Threads.@spawn begin
        pos = 1
        len = 0
        try
            while true
                val = nothing
                err = nothing
                try
                    val, pos, len = _readresponse(Any, client.socket, client.repsonse_buffer, client.debug, pos, len)
                catch e
                    err = CapturedException(e, Base.catch_backtrace())
                end
                put!(client.responses, Response(val, err))
                err !== nothing && throw(err)
            end
        catch e
            close(client.responses)
        end
    end
    return
end

function execute(::Type{T}, client::Client, command::String) where {T}
    writemessage(client.socket, command)
    resp = take!(client.responses)
    if resp.error !== nothing
        throw(resp.error)
    end
    return resp.value::T
end

execute(::Type{T}, client::Client, command::Command) where {T} = execute(T, client, command.cmd)
execute(client::Client, command::String) = execute(String, client, command)
execute(client::Client, cmd::Command) = execute(client, cmd.cmd)

function execute_batch(client::Client, cmds::Vector{Command})
    batch_str = join(cmds .|> c -> c.cmd, "")
    client.debug && @info "Batch Command: $batch_str"
    writemessage(client.socket, batch_str)
    results = Vector{Any}(undef, length(cmds))
    err = nothing
    for i in 1:length(cmds)
        resp = take!(client.responses)
        if resp.error !== nothing
            err = resp.error
        end
        results[i] = resp.value
    end
    if err !== nothing
        throw(err)
    end
    return results
end

function writemessage(socket, data::String)
    write(socket, data)
    flush(socket)
end

@inline function findnewline(socket, buf, pos, len)
    while true
        if pos > len
            pos, len = getmoredata!(socket, buf, pos, len)
        end
        @inbounds buf[pos] == UInt8('\r') && return pos, len
        pos += 1
    end
    @assert false
end

# read a single redis response from the socket into buf
readresponse(client::Client) = readresponse(String, client.socket, client.repsonse_buffer, client.debug)
readresponse(io::IO) = readresponse(String, io)
readresponse(::Type{T}, socket, buf=Vector{UInt8}(undef, 4096), debug=false, start=1, len=0) where {T} =
    _readresponse(T, socket, buf, debug, start, len)[1]

function getmoredata!(socket, buf, pos, len)
    eof(socket) && throw(EOFError())
    # Move any remaining bytes to the start of the buffer
    nrem = len - pos + 1
    if nrem > 0
        @inbounds copyto!(buf, 1, buf, pos, nrem)
    end
    # Read available bytes into the buffer after the remaining bytes
    nbytes = bytesavailable(socket)
    resize!(buf, nrem + nbytes)
    unsafe_read(socket, pointer(buf, nrem + 1), nbytes)
    len = nrem + nbytes
    pos = 1
    @assert len > 0
    return pos, len
end

@inline function _readresponse(::Type{T}, socket, buf=Vector{UInt8}(undef, 4096), debug=true, pos=1, len=0) where {T}
    start = pos
    GC.@preserve buf begin
        while true
            if pos > len
                pos, len = getmoredata!(socket, buf, pos, len)
                start = pos
            end
            type = @inbounds buf[start]
            debug && @info "RESP type: $(Char(type))"
            if type == UInt8('+')
                pos, len = findnewline(socket, buf, pos, len)
                return unsafe_string(pointer(buf, start + 1), pos - start - 1), pos + 2, len
            elseif type == UInt8('-')
                throw(RedisError(unsafe_string(pointer(buf, start + 1), (len - 2) - start)))
            elseif type == UInt8(':')
                (T === Int || T === Any) || throw(RedisError("Receiving redis integer response, but `$(T)` is not an integer type"))
                pos, len = findnewline(socket, buf, pos, len)
                return Parsers.parse(Int, buf, Parsers.OPTIONS, start + 1, pos - 1), pos + 2, len
            elseif type == UInt8('$')
                pos, len = findnewline(socket, buf, pos, len)
                bulklen = Parsers.parse(Int, buf, Parsers.OPTIONS, start + 1, pos - 1)
                debug && @info "Bulklen: $bulklen"
                bulklen == -1 && return nothing, pos + 2, len
                bulkStart = pos + 2
                pos = bulkStart + bulklen
                while pos > len
                    pos, len = getmoredata!(socket, buf, pos, len)
                    start = pos
                end
                return unsafe_string(pointer(buf, bulkStart), bulklen), pos + 2, len
            elseif type == UInt8('*')
                (T <: AbstractArray || T === Any) || throw(RedisError("Receiving redis array response, but `$(T)` is not an array type"))
                pos, len = findnewline(socket, buf, pos, len)
                count = Parsers.parse(Int, buf, Parsers.OPTIONS, start + 1, pos - 1)
                debug && @info "Array count: $count"
                count == -1 && return nothing, pos + 2, len
                pos += 2
                results = (T === Any ? Vector{Any} : T)(undef, count)
                for i in 1:count
                    results[i], pos, len = _readresponse(eltype(T), socket, buf, debug, pos, len)
                end
                return results, pos, len
            else
                @error "dumping redis buffer" start=start pos=pos len=len
                println(String(buf))
                close(socket)
                throw(RedisError("Unexpected RESP type: '$(Char(type))'"))
            end
        end
    end
    throw(EOFError())
end

function set(client::Client, key::AbstractString, value::AbstractString; nx::Bool=false, xx::Bool=false, ex::Int=0, px::Int=0)
    command = Commands.set(key, value; nx=nx, xx=xx, ex=ex, px=px)
    client.debug && @info "SET Command: $(command.cmd)"
    return execute(client, command)
end

function mset(client::Client, pairs::Pair{String,String}...)
    command = Commands.mset(pairs...)
    client.debug && @info "MSET Command: $(command.cmd)"
    return execute(client, command)
end

function get(client::Client, key::AbstractString)
    command = Commands.get(key)
    client.debug && @info "GET Command: $(command.cmd)"
    return execute(client, command)
end

function del(client::Client, key::AbstractString)
    command = Commands.del(key)
    client.debug && @info "DEL Command: $(command.cmd)"
    return execute(Int, client, command)
end

function append(client::Client, key::AbstractString, value::AbstractString)
    command = Commands.append(key, value)
    client.debug && @info "APPEND Command: $(command.cmd)"
    return execute(Int, client, command)
end

function incrby(client::Client, key::AbstractString, increment::Int)
    command = Commands.incrby(key, increment)
    client.debug && @info "INCRBY Command: $(command.cmd)"
    return execute(client, command)
end

function mget(client::Client, keys::AbstractString...)
    command = Commands.mget(keys...)
    client.debug && @info "MGET Command: $(command.cmd)"
    return execute(Vector{Union{String, Nothing}}, client, command)
end

function scan(client::Client, cursor::AbstractString="0"; match::AbstractString="")
    command = Commands.scan(cursor; match=match)
    client.debug && @info "SCAN Command: $(command.cmd)"
    return execute(Any, client, command)
end

struct Scan
    client::Client
    match::String
end

Scan(client) = Scan(client, "")

function Base.iterate(ss::Scan, state=nothing)
    if state === nothing
        cursor, keys = scan(ss.client, "0"; match=ss.match)
        i = 1
    else
        (cursor, keys), i = state
        if i > length(keys)
            cursor == "0" && return nothing
            cursor, keys = scan(ss.client, cursor; match=ss.match)
            i = 1
        end
    end
    return keys[i], ((cursor, keys), i+1)
end

function zrange(client::Client, key::AbstractString, min::AbstractString, max::AbstractString, bylex::Bool=false, useLegacyCommand::Bool=true)
    command = Commands.zrange(key, min, max, bylex, useLegacyCommand)
    client.debug && @info "ZRANGE Command: $(command.cmd)"
    return execute(Vector{String}, client, command)
end

function zadd(client::Client, key::AbstractString, score::AbstractString, member::AbstractString)
    command = Commands.zadd(key, score, member)
    client.debug && @info "ZADD Command: $(command.cmd)"
    return execute(Int, client, command)
end

function zcard(client::Client, key::AbstractString)
    command = Commands.zcard(key)
    client.debug && @info "ZCARD Command: $(command.cmd)"
    return execute(Int, client, command)
end

function zrem(client::Client, key::AbstractString, member::AbstractString)
    command = Commands.zrem(key, member)
    client.debug && @info "ZREM Command: $(command.cmd)"
    return execute(Int, client, command)
end

function zrevrangebyscore(client::Client, key::AbstractString, max::AbstractString, min::AbstractString; limit_start::Int=0, limit_count::Int=0)
    command = Commands.zrevrangebyscore(key, max, min; limit_start=limit_start, limit_count=limit_count)
    client.debug && @info "ZREVRANGEBYSCORE Command: $(command.cmd)"
    return execute(Vector{String}, client, command)
end

function zremrangebyrank(client::Client, key::AbstractString, start::Int, stop::Int)
    command = Commands.zremrangebyrank(key, start, stop)
    client.debug && @info "ZREMRANGEBYRANK Command: $(command.cmd)"
    return execute(Int, client, command)
end

function zrevrange(client::Client, key::AbstractString, start::Int, stop::Int; withscores::Bool=false)
    command = Commands.zrevrange(key, start, stop; withscores=withscores)
    client.debug && @info "ZREVRANGE Command: $(command.cmd)"
    return execute(Vector{String}, client, command)
end

function zscan(client::Client, key::AbstractString, cursor::AbstractString="0"; match::AbstractString="")
    command = Commands.zscan(key, cursor; match=match)
    client.debug && @info "ZSCAN Command: $(command.cmd)"
    return execute(Any, client, command)
end

struct Zscan
    client::Client
    key::String
    match::String
end

Zscan(client, key) = Zscan(client, key, "")

function Base.iterate(ss::Zscan, state=nothing)
    if state === nothing
        cursor, members = zscan(ss.client, ss.key; match=ss.match)
        i = 1
    else
        (cursor, members), i = state
        if i > length(members)
            cursor == "0" && return nothing
            cursor, members = zscan(ss.client, ss.key, cursor; match=ss.match)
            i = 1
        end
    end
    return members[i], ((cursor, members), i+1)
end

function xadd(client::Client, key::AbstractString, id::AbstractString, field::AbstractString, value::AbstractString)
    command = Commands.xadd(key, id, field, value)
    client.debug && @info "XADD Command: $(command.cmd)"
    return execute(client, command)
end

function xadd(client::Client, key::AbstractString, id::AbstractString, field::AbstractString, value::AbstractString, maxlen::Int)
    command = Commands.xadd(key, id, field, value, maxlen)
    client.debug && @info "XADD Command: $(command.cmd)"
    return execute(client, command)
end

function xdel(client::Client, key::AbstractString, id::AbstractString)
    command = Commands.xdel(key, id)
    client.debug && @info "XDEL Command: $(command.cmd)"
    return execute(Int, client, command)
end

function xrange(client::Client, key::AbstractString, start::AbstractString, stop::AbstractString)
    command = Commands.xrange(key, start, stop)
    client.debug && @info "XRANGE Command: $(command.cmd)"
    return execute(Any, client, command)
end

function xtrim(client::Client, key::AbstractString, maxlen::Int, approximate::Bool=false)
    command = Commands.xtrim(key, maxlen, approximate)
    client.debug && @info "XTRIM Command: $(command.cmd)"
    return execute(Int, client, command)
end

function sadd(client::Client, key::AbstractString, member::AbstractString)
    command = Commands.sadd(key, member)
    client.debug && @info "SADD Command: $(command.cmd)"
    return execute(Int, client, command)
end

function srem(client::Client, key::AbstractString, member::AbstractString)
    command = Commands.srem(key, member)
    client.debug && @info "SREM Command: $(command.cmd)"
    return execute(Int, client, command)
end

function scard(client::Client, key::AbstractString)
    command = Commands.scard(key)
    client.debug && @info "SCARD Command: $(command.cmd)"
    return execute(Int, client, command)
end

function sscan(client::Client, key::AbstractString, cursor::AbstractString="0"; match::AbstractString="")
    command = Commands.sscan(key, cursor; match=match)
    client.debug && @info "SSCAN Command: $(command.cmd)"
    return execute(Any, client, command)
end

function smembers(client::Client, key::AbstractString)
    command = Commands.smembers(key)
    client.debug && @info "SMEMBERS Command: $(command.cmd)"
    return execute(Vector{String}, client, command)
end

struct Sscan
    client::Client
    key::String
    match::String
end

Sscan(client, key) = Sscan(client, key, "")

function Base.iterate(ss::Sscan, state=nothing)
    if state === nothing
        cursor, members = sscan(ss.client, ss.key; match=ss.match)
        i = 1
    else
        (cursor, members), i = state
        if i > length(members)
            cursor == "0" && return nothing
            cursor, members = sscan(ss.client, ss.key, cursor; match=ss.match)
            i = 1
        end
    end
    return members[i], ((cursor, members), i+1)
end

function multi(client::Client)
    command = Commands.multi()
    client.debug && @info "MULTI Command: $(command.cmd)"
    return execute(client, command)
end

function exec(client::Client)
    command = Commands.exec()
    client.debug && @info "EXEC Command: $(command.cmd)"
    return execute(Vector{String}, client, command)
end

function discard(client::Client)
    command = Commands.discard()
    client.debug && @info "DISCARD Command: $(command.cmd)"
    return execute(client, command)
end

function expire(client::Client, key::AbstractString, seconds::Int)
    command = Commands.expire(key, seconds)
    client.debug && @info "EXPIRE Command: $(command.cmd)"
    return execute(Int, client, command)
end

function publish(client::Client, channel::AbstractString, message::AbstractString)
    command = Commands.publish(channel, message)
    client.debug && @info "PUBLISH Command: $(command.cmd)"
    return execute(Int, client, command)
end

function hdel(client::Client, key::AbstractString, field::AbstractString)
    command = Commands.hdel(key, field)
    client.debug && @info "HDEL Command: $(command.cmd)"
    return execute(Int, client, command)
end

function hget(client::Client, key::AbstractString, field::AbstractString)
    command = Commands.hget(key, field)
    client.debug && @info "HGET Command: $(command.cmd)"
    return execute(client, command)
end

function hlen(client::Client, key::AbstractString)
    command = Commands.hlen(key)
    client.debug && @info "HLEN Command: $(command.cmd)"
    return execute(Int, client, command)
end

function hset(client::Client, key::AbstractString, field::AbstractString, value::AbstractString)
    command = Commands.hset(key, field, value)
    client.debug && @info "HSET Command: $(command.cmd)"
    return execute(Int, client, command)
end

function hscan(client::Client, key::AbstractString, cursor::Int64; match::Union{Nothing, AbstractString}=nothing)
    command = Commands.hscan(key, cursor; match=match)
    client.debug && @info "HSCAN Command: $(command.cmd)"
    return execute(Any, client, command)
end

struct Hscan
    client::Client
    key::String
    match::String
end

Hscan(client, key) = Hscan(client, key, "")

function Base.iterate(ss::Hscan, state=nothing)
    if state === nothing
        cursor, members = hscan(ss.client, ss.key, "0"; match=ss.match)
        i = 1
    else
        (cursor, members), i = state
        if i > length(members)
            cursor == "0" && return nothing
            cursor, members = hscan(ss.client, ss.key, cursor; match=ss.match)
            i = 1
        end
    end
    return members[i], ((cursor, members), i+1)
end

function rpush(client::Client, key::AbstractString, value::AbstractString)
    command = Commands.rpush(key, value)
    client.debug && @info "RPUSH Command: $(command.cmd)"
    return execute(Int, client, command)
end

function lindex(client::Client, key::AbstractString, index::Int64)
    command = Commands.lindex(key, index)
    client.debug && @info "LINDEX Command: $(command.cmd)"
    return execute(client, command)
end

function lpush(client::Client, key::AbstractString, value::AbstractString)
    command = Commands.lpush(key, value)
    client.debug && @info "LPUSH Command: $(command.cmd)"
    return execute(Int, client, command)
end

function ltrim(client::Client, key::AbstractString, start::Int64, stop::Int64)
    command = Commands.ltrim(key, start, stop)
    client.debug && @info "LTRIM Command: $(command.cmd)"
    return execute(Int, client, command)
end

function lrange(client::Client, key::AbstractString, start::Int64, stop::Int64)
    command = Commands.lrange(key, start, stop)
    client.debug && @info "LRANGE Command: $(command.cmd)"
    return execute(Vector{String}, client, command)
end

function lrem(client::Client, key::AbstractString, count::Int64, value::AbstractString)
    command = Commands.lrem(key, count, value)
    client.debug && @info "LREM Command: $(command.cmd)"
    return execute(Int, client, command)
end

function geoadd(client::Client, key::AbstractString, longitude::AbstractString, latitude::AbstractString, member::AbstractString)
    command = Commands.geoadd(key, longitude, latitude, member)
    client.debug && @info "GEOADD Command: $(command.cmd)"
    return execute(Int, client, command)
end

function geodist(client::Client, key::AbstractString, member1::AbstractString, member2::AbstractString, unit::AbstractString="m")
    command = Commands.geodist(key, member1, member2, unit)
    client.debug && @info "GEODIST Command: $(command.cmd)"
    return execute(client, command)
end

function geohash(client::Client, key::AbstractString, members::AbstractString...)
    command = Commands.geohash(key, members...)
    client.debug && @info "GEOHASH Command: $(command.cmd)"
    return execute(Any, client, command)
end

function geopos(client::Client, key::AbstractString, members::AbstractString...)
    command = Commands.geopos(key, members...)
    client.debug && @info "GEOPOS Command: $(command.cmd)"
    return execute(Any, client, command)
end

function geosearch(client::Client, key::AbstractString, longitude::AbstractString, latitude::AbstractString, radius::AbstractString, unit::AbstractString)
    command = Commands.geosearch(key, longitude, latitude, radius, unit)
    client.debug && @info "GEOSEARCH Command: $(command.cmd)"
    return execute(Vector{String}, client, command)
end

function georadius(client::Client, key::AbstractString, longitude::AbstractString, latitude::AbstractString, radius::AbstractString, unit::AbstractString;
    asc::Bool=true, withcoord::Bool=false, withdist::Bool=false, withhash::Bool=false, count::Union{Nothing, Int}=nothing, store::Union{Nothing, String}=nothing, storedist::Union{Nothing, String}=nothing)
    command = Commands.georadius(key, longitude, latitude, radius, unit; asc=asc, withcoord=withcoord, withdist=withdist, withhash=withhash, count=count, store=store, storedist=storedist)
    client.debug && @info "GEORADIUS Command: $(command.cmd)"
    return execute(Any, client, command)
end

end # module