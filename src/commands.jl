module Commands

export Command, set, mset, append, incrby, get, mget, del, scan, zrange, zadd, zcard, zrem, zrevrangebyscore, zremrangebyrank, zrevrange, zscan, xadd, xdel, xrange, xtrim, sadd, srem, scard, sscan, smembers, multi, exec, discard, expire, publish, hdel, hget, hlen, hset, hscan, rpush, lindex, lpush, ltrim, lrange, lrem, geoadd, geodist, geohash, geopos, geosearch, georadius

struct Command
    cmd::String
end

function set(key::AbstractString, value::AbstractString; nx::Bool=false, xx::Bool=false, ex::Int=0, px::Int=0)
    narg = 3 + nx + xx + (ex > 0 ? 2 : 0) + (px > 0 ? 2 : 0)
    command = "*$narg\r\n\$3\r\nSET\r\n\$$(sizeof(key))\r\n$key\r\n\$$(sizeof(value))\r\n$value\r\n"
    if nx
        command *= "\$2\r\nNX\r\n"
    end
    if xx
        command *= "\$2\r\nXX\r\n"
    end
    if ex > 0
        command *= "\$2\r\nEX\r\n\$$(sizeof(string(ex)))\r\n$(string(ex))\r\n"
    end
    if px > 0
        command *= "\$2\r\nPX\r\n\$$(sizeof(string(px)))\r\n$(string(px))\r\n"
    end
    return Command(command)
end

function mset(pairs::Pair{String, String}...)
    n_args = 1 + 2 * length(pairs)
    command = "*$n_args\r\n\$4\r\nMSET\r\n"
    for (key, value) in pairs
        command *= "\$$(length(key))\r\n$key\r\n"
        command *= "\$$(length(value))\r\n$value\r\n"
    end
    return Command(command)
end

function append(key::AbstractString, value::AbstractString)
    command = "*3\r\n\$6\r\nAPPEND\r\n\$$(length(key))\r\n$key\r\n\$$(sizeof(value))\r\n$value\r\n"
    return Command(command)
end

function incrby(key::AbstractString, increment::Int)
    incr = string(increment)
    command = "*3\r\n\$6\r\nINCRBY\r\n\$$(length(key))\r\n$key\r\n\$$(length(incr))\r\n$incr\r\n"
    return Command(command)
end

function get(key::AbstractString)
    command = "*2\r\n\$3\r\nGET\r\n\$$(length(key))\r\n$key\r\n"
    return Command(command)
end

function mget(keys::AbstractString...)
    narg = 1 + length(keys)
    command = "*$narg\r\n\$4\r\nMGET\r\n"
    for key in keys
        command *= "\$$(length(key))\r\n$key\r\n"
    end
    return Command(command)
end

function del(key::AbstractString)
    command = "*2\r\n\$3\r\nDEL\r\n\$$(length(key))\r\n$key\r\n"
    return Command(command)
end

function scan(cursor::AbstractString="0"; match::AbstractString="")
    cnt = 2 + (match !== "" ? 2 : 0)
    command = "*$cnt\r\n\$4\r\nSCAN\r\n\$$(length(cursor))\r\n$cursor\r\n"
    if !isempty(match)
        command *= "\$5\r\nMATCH\r\n\$$(length(match))\r\n$match\r\n"
    end
    return Command(command)
end

function zrange(key::AbstractString, min::AbstractString, max::AbstractString, bylex::Bool=false, useLegacyCommand::Bool=true)
    if useLegacyCommand
        if bylex
            command = "*4\r\n\$11\r\nZRANGEBYLEX\r\n\$$(length(key))\r\n$key\r\n\$$(length(min))\r\n$min\r\n\$$(length(max))\r\n$max\r\n"
        else
            command = "*4\r\n\$14\r\nZRANGEBYSCORE\r\n\$$(length(key))\r\n$key\r\n\$$(length(min))\r\n$min\r\n\$$(length(max))\r\n$max\r\n"
        end
    else
        if bylex
            command = "*5\r\n\$6\r\nZRANGE\r\n\$$(length(key))\r\n$key\r\n\$$(length(min))\r\n$min\r\n\$$(length(max))\r\n$max\r\n\$5\r\nBYLEX\r\n"
        else
            command = "*4\r\n\$6\r\nZRANGE\r\n\$$(length(key))\r\n$key\r\n\$$(length(min))\r\n$min\r\n\$$(length(max))\r\n$max\r\n"
        end
    end
    return Command(command)
end

function zadd(key::AbstractString, score::AbstractString, member::AbstractString)
    command = "*4\r\n\$4\r\nZADD\r\n\$$(length(key))\r\n$key\r\n\$$(length(score))\r\n$score\r\n\$$(length(member))\r\n$member\r\n"
    return Command(command)
end

function zcard(key::AbstractString)
    command = "*2\r\n\$5\r\nZCARD\r\n\$$(length(key))\r\n$key\r\n"
    return Command(command)
end

function zrem(key::AbstractString, member::AbstractString)
    command = "*3\r\n\$4\r\nZREM\r\n\$$(length(key))\r\n$key\r\n\$$(length(member))\r\n$member\r\n"
    return Command(command)
end

function zrevrangebyscore(key::AbstractString, max::AbstractString, min::AbstractString; limit_start::Int=0, limit_count::Int=0)
    narg = 4 + (limit_count > 0 ? 3 : 0)
    command = "*$narg\r\n\$16\r\nZREVRANGEBYSCORE\r\n\$$(length(key))\r\n$key\r\n\$$(length(max))\r\n$max\r\n\$$(length(min))\r\n$min\r\n"
    if limit_count > 0
        command *= "\$5\r\nLIMIT\r\n\$$(length(string(limit_start)))\r\n$limit_start\r\n\$$(length(string(limit_count)))\r\n$limit_count\r\n"
    end
    return Command(command)
end

function zremrangebyrank(key::AbstractString, start::Int, stop::Int)
    command = "*4\r\n\$15\r\nZREMRANGEBYRANK\r\n\$$(length(key))\r\n$key\r\n\$$(length(string(start)))\r\n$start\r\n\$$(length(string(stop)))\r\n$stop\r\n"
    return Command(command)
end

function zrevrange(key::AbstractString, start::Int, stop::Int; withscores::Bool=false)
    nargs = 4 + withscores
    command = "*$nargs\r\n\$9\r\nZREVRANGE\r\n\$$(length(key))\r\n$key\r\n\$$(length(string(start)))\r\n$start\r\n\$$(length(string(stop)))\r\n$stop\r\n"
    if withscores
        command *= "\$10\r\nWITHSCORES\r\n"
    end
    return Command(command)
end

function zscan(key::AbstractString, cursor::AbstractString="0"; match::AbstractString="")
    command = "*3\r\n\$5\r\nZSCAN\r\n\$$(length(key))\r\n$key\r\n\$$(length(cursor))\r\n$cursor\r\n"
    if !isempty(match)
        command *= "\$5\r\nMATCH\r\n\$$(length(match))\r\n$match\r\n"
    end
    return Command(command)
end

function xadd(key::AbstractString, id::AbstractString, field::AbstractString, value::AbstractString)
    command = "*5\r\n\$4\r\nXADD\r\n\$$(length(key))\r\n$key\r\n\$$(length(id))\r\n$id\r\n\$$(length(field))\r\n$field\r\n\$$(length(value))\r\n$value\r\n"
    return Command(command)
end

function xadd(key::AbstractString, id::AbstractString, field::AbstractString, value::AbstractString, maxlen::Int)
    command = "*7\r\n\$4\r\nXADD\r\n\$$(length(key))\r\n$key\r\n\$6\r\nMAXLEN\r\n\$1\r\n~\r\n\$$(length(string(maxlen)))\r\n$maxlen\r\n\$$(length(id))\r\n$id\r\n\$$(length(field))\r\n$field\r\n\$$(length(value))\r\n$value\r\n"
    return Command(command)
end

function xdel(key::AbstractString, id::AbstractString)
    command = "*3\r\n\$4\r\nXDEL\r\n\$$(length(key))\r\n$key\r\n\$$(length(id))\r\n$id\r\n"
    return Command(command)
end

function xrange(key::AbstractString, start::AbstractString, stop::AbstractString)
    command = "*4\r\n\$6\r\nXRANGE\r\n\$$(length(key))\r\n$key\r\n\$$(length(start))\r\n$start\r\n\$$(length(stop))\r\n$stop\r\n"
    return Command(command)
end

function xtrim(key::AbstractString, maxlen::Int, approximate::Bool=false)
    if approximate
        command = "*5\r\n\$5\r\nXTRIM\r\n\$$(length(key))\r\n$key\r\n\$6\r\nMAXLEN\r\n\$1\r\n~\r\n\$$(length(string(maxlen)))\r\n$maxlen\r\n"
    else
        command = "*4\r\n\$5\r\nXTRIM\r\n\$$(length(key))\r\n$key\r\n\$6\r\nMAXLEN\r\n\$$(length(string(maxlen)))\r\n$maxlen\r\n"
    end
    return Command(command)
end

function sadd(key::AbstractString, member::AbstractString)
    command = "*3\r\n\$4\r\nSADD\r\n\$$(length(key))\r\n$key\r\n\$$(length(member))\r\n$member\r\n"
    return Command(command)
end

function srem(key::AbstractString, member::AbstractString)
    command = "*3\r\n\$4\r\nSREM\r\n\$$(length(key))\r\n$key\r\n\$$(length(member))\r\n$member\r\n"
    return Command(command)
end

function scard(key::AbstractString)
    command = "*2\r\n\$5\r\nSCARD\r\n\$$(length(key))\r\n$key\r\n"
    return Command(command)
end

function sscan(key::AbstractString, cursor::AbstractString="0"; match::AbstractString="")
    command = "*3\r\n\$5\r\nSSCAN\r\n\$$(length(key))\r\n$key\r\n\$$(length(cursor))\r\n$cursor\r\n"
    if !isempty(match)
        command *= "\$5\r\nMATCH\r\n\$$(length(match))\r\n$match\r\n"
    end
    return Command(command)
end

function smembers(key::AbstractString)
    command = "*2\r\n\$8\r\nSMEMBERS\r\n\$$(length(key))\r\n$key\r\n"
    return Command(command)
end

function multi()
    command = "*1\r\n\$5\r\nMULTI\r\n"
    return Command(command)
end

function exec()
    command = "*1\r\n\$4\r\nEXEC\r\n"
    return Command(command)
end

function discard()
    command = "*1\r\n\$7\r\nDISCARD\r\n"
    return Command(command)
end

function expire(key::AbstractString, seconds::Int)
    command = "*3\r\n\$6\r\nEXPIRE\r\n\$$(length(key))\r\n$key\r\n\$$(length(string(seconds)))\r\n$seconds\r\n"
    return Command(command)
end

function publish(channel::AbstractString, message::AbstractString)
    command = "*3\r\n\$7\r\nPUBLISH\r\n\$$(length(channel))\r\n$channel\r\n\$$(length(message))\r\n$message\r\n"
    return Command(command)
end

function hdel(key::AbstractString, field::AbstractString)
    command = "*3\r\n\$4\r\nHDEL\r\n\$$(length(key))\r\n$key\r\n\$$(length(field))\r\n$field\r\n"
    return Command(command)
end

function hget(key::AbstractString, field::AbstractString)
    command = "*3\r\n\$4\r\nHGET\r\n\$$(length(key))\r\n$key\r\n\$$(length(field))\r\n$field\r\n"
    return Command(command)
end

function hlen(key::AbstractString)
    command = "*2\r\n\$4\r\nHLEN\r\n\$$(length(key))\r\n$key\r\n"
    return Command(command)
end

function hset(key::AbstractString, field::AbstractString, value::AbstractString)
    command = "*4\r\n\$4\r\nHSET\r\n\$$(length(key))\r\n$key\r\n\$$(length(field))\r\n$field\r\n\$$(length(value))\r\n$value\r\n"
    return Command(command)
end

function hscan(key::AbstractString, cursor::Int64; match::Union{Nothing, AbstractString}=nothing)
    command = "*3\r\n\$5\r\nHSCAN\r\n\$$(length(key))\r\n$key\r\n\$$(length(string(cursor)))\r\n$cursor\r\n"
    if match !== nothing
        command *= "\$5\r\nMATCH\r\n\$$(length(match))\r\n$match\r\n"
    end
    return Command(command)
end

function rpush(key::AbstractString, value::AbstractString)
    command = "*3\r\n\$5\r\nRPUSH\r\n\$$(length(key))\r\n$key\r\n\$$(length(value))\r\n$value\r\n"
    return Command(command)
end

function lindex(key::AbstractString, index::Int64)
    command = "*3\r\n\$6\r\nLINDEX\r\n\$$(length(key))\r\n$key\r\n\$$(length(string(index)))\r\n$index\r\n"
    return Command(command)
end

function lpush(key::AbstractString, value::AbstractString)
    command = "*3\r\n\$5\r\nLPUSH\r\n\$$(length(key))\r\n$key\r\n\$$(length(value))\r\n$value\r\n"
    return Command(command)
end

function ltrim(key::AbstractString, start::Int64, stop::Int64)
    command = "*4\r\n\$5\r\nLTRIM\r\n\$$(length(key))\r\n$key\r\n\$$(length(string(start)))\r\n$start\r\n\$$(length(string(stop)))\r\n$stop\r\n"
    return Command(command)
end

function lrange(key::AbstractString, start::Int64, stop::Int64)
    command = "*4\r\n\$6\r\nLRANGE\r\n\$$(length(key))\r\n$key\r\n\$$(length(string(start)))\r\n$start\r\n\$$(length(string(stop)))\r\n$stop\r\n"
    return Command(command)
end

function lrem(key::AbstractString, count::Int64, value::AbstractString)
    command = "*4\r\n\$4\r\nLREM\r\n\$$(length(key))\r\n$key\r\n\$$(length(string(count)))\r\n$count\r\n\$$(length(value))\r\n$value\r\n"
    return Command(command)
end

function geoadd(key::AbstractString, longitude::AbstractString, latitude::AbstractString, member::AbstractString)
    command = "*5\r\n\$6\r\nGEOADD\r\n\$$(length(key))\r\n$key\r\n\$$(length(longitude))\r\n$longitude\r\n\$$(length(latitude))\r\n$latitude\r\n\$$(length(member))\r\n$member\r\n"
    return Command(command)
end

function geodist(key::AbstractString, member1::AbstractString, member2::AbstractString, unit::AbstractString="m")
    command = "*5\r\n\$7\r\nGEODIST\r\n\$$(length(key))\r\n$key\r\n\$$(length(member1))\r\n$member1\r\n\$$(length(member2))\r\n$member2\r\n\$$(length(unit))\r\n$unit\r\n"
    return Command(command)
end

function geohash(key::AbstractString, members::AbstractString...)
    n_args = 2 + length(members)
    command = "*$n_args\r\n\$7\r\nGEOHASH\r\n\$$(length(key))\r\n$key\r\n"
    for member in members
        command *= "\$$(length(member))\r\n$member\r\n"
    end
    return Command(command)
end

function geopos(key::AbstractString, members::AbstractString...)
    n_args = 2 + length(members)
    command = "*$n_args\r\n\$6\r\nGEOPOS\r\n\$$(length(key))\r\n$key\r\n"
    for member in members
        command *= "\$$(length(member))\r\n$member\r\n"
    end
    return Command(command)
end

function geosearch(key::AbstractString, longitude::AbstractString, latitude::AbstractString, radius::AbstractString, unit::AbstractString)
    command = "*8\r\n\$9\r\nGEOSEARCH\r\n\$$(length(key))\r\n$key\r\n\$10\r\nFROMLONLAT\r\n\$$(length(longitude))\r\n$longitude\r\n\$$(length(latitude))\r\n$latitude\r\n\$8\r\nBYRADIUS\r\n\$$(length(radius))\r\n$radius\r\n\$$(length(unit))\r\n$unit\r\n"
    return Command(command)
end

function georadius(key::AbstractString, longitude::AbstractString, latitude::AbstractString, radius::AbstractString, unit::AbstractString; asc::Bool=true, withcoord::Bool=false, withdist::Bool=false, withhash::Bool=false, count::Union{Nothing, Int}=nothing, store::Union{Nothing, String}=nothing, storedist::Union{Nothing, String}=nothing)
    n_args = 7
    if withcoord
        n_args += 1
    end
    if withdist
        n_args += 1
    end
    if withhash
        n_args += 1
    end
    if count !== nothing
        n_args += 2
    end
    if store !== nothing
        n_args += 2
    end
    if storedist !== nothing
        n_args += 2
    end
    command = "*$n_args\r\n\$9\r\nGEORADIUS\r\n\$$(length(key))\r\n$key\r\n\$$(length(longitude))\r\n$longitude\r\n\$$(length(latitude))\r\n$latitude\r\n\$$(length(radius))\r\n$radius\r\n\$$(length(unit))\r\n$unit\r\n"
    if asc
        command *= "\$3\r\nASC\r\n"
    else
        command *= "\$4\r\nDESC\r\n"
    end
    if withcoord
        command *= "\$9\r\nWITHCOORD\r\n"
    end
    if withdist
        command *= "\$8\r\nWITHDIST\r\n"
    end
    if withhash
        command *= "\$8\r\nWITHHASH\r\n"
    end
    if count !== nothing
        command *= "\$5\r\nCOUNT\r\n\$$(length(string(count)))\r\n$count\r\n"
    end
    if store !== nothing
        command *= "\$5\r\nSTORE\r\n\$$(length(store))\r\n$store\r\n"
    end
    if storedist !== nothing
        command *= "\$9\r\nSTOREDIST\r\n\$$(length(storedist))\r\n$storedist\r\n"
    end
    return Command(command)
end

end # module Commands
