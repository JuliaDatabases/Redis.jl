"""
        StreamScanner

Provides a convenient streaming interface for the Redis SCAN, SSCAN, ZSCAN and HSCAN commands. Updating the
cursor after each scan is handled under-the-hood.

StreamScanner is an abstract type, with 4 concrete implementations based on the type of key scanned:
* `KeyScanner`          global key space scans
* `SetScanner`          set scans
* `OrderedSetScanner`   zset scans
* `HashScanner`         hash field scans

# Notes
from http://redis.io/commands/scan:
    * The SCAN family of commands only offer limited guarantees about the returned elements since the collection
    that we incrementally iterate can change during the iteration process.
    * Basically with COUNT the user specified _the amount of work that should be done at every call in order to
      retrieve elements from the collection_. This is __just a hint__ for the implementation, however generally
      speaking this is what you could expect most of the times from the implementation.
"""
abstract StreamScanner

"""
        next!(ss::StreamScanner; count=1)

Retrieve the next scan item(s).

# Arguments
* `ss` :        a concrete StreamScanner object
* `count` :     the number of items requested per scan. This is only a hint.
"""
function next! end

import Base: collect
"""
        collect(ss::StreamScanner)

Scan until complete.

# Arguments
* `ss` :        a concrete StreamScanner object
"""
function collect end

"""
        collectAsync!(ss, arr, myCallback)

Update array asynchronously with callback when complete.

# Arguments
* `ss` :            a StreamScanner
* `arr` :           predefined Collection to accumulate results of scan
* `myCallback` :    called with `arr` as parameter, defaults to a 'do nothing' method

# Motivation
Say we have many keys to scan, this prevents block.  The result array will be updated
asynchronously until complete. This can be checked, for example, by calling `length(arr)`
while running a long scan.
"""
function collectAsync! end


type KeyScanner <: StreamScanner
    conn::RedisConnection
    cursor::AbstractString
    match::AbstractString
    count::Int64
    KeyScanner(conn::RedisConnection, match::AbstractString, count::Int64) = new(conn, "0", match, count)
end

function next!(KS::KeyScanner; count=KS.count)
    KS.cursor, result = scan(KS.conn, parse(Int64, KS.cursor), "MATCH", KS.match, "COUNT", count)
    collect(result)
end

type SetScanner <: StreamScanner
    conn::RedisConnection
    key::AbstractString
    cursor::AbstractString
    match::AbstractString
    count::Int64
    function SetScanner(conn::RedisConnection, key::AbstractString, match::AbstractString, count::Int64)
        if keytype(conn, key) != "set"
            throw(ProtocolException("Wrong key type: expected Set; received $(keytype(conn, key))"))
        end
        new(conn, key, "0", match, count)
    end
end

function next!(SS::SetScanner; count=SS.count)
    SS.cursor, result = sscan(SS.conn, SS.key, parse(Int64, SS.cursor), "MATCH", SS.match, "COUNT", count)
    collect(result)
end

type OrderedSetScanner <: StreamScanner
    conn::RedisConnection
    key::AbstractString
    cursor::AbstractString
    match::AbstractString
    count::Int64
    function OrderedSetScanner(conn::RedisConnection, key::AbstractString, match::AbstractString, count::Int64)
        if keytype(conn, key) != "zset"
            throw(ProtocolException("Wrong key type: expected OrderedSet; received $(keytype(conn, key))"))
        end
        new(conn, key, "0", match, count)
    end
end

function next!(OS::OrderedSetScanner; count=OS.count)
    OS.cursor, response = zscan(OS.conn, OS.key, parse(Int64, OS.cursor), "MATCH", OS.match, "COUNT", count)
    r = OrderedSet{Tuple{Float64, AbstractString}}()
    for i=1:2:length(response)
        push!(r, (parse(Float64, response[i+1]), response[i]))
    end
    r
end

type HashScanner <: StreamScanner
    conn::RedisConnection
    key::AbstractString
    cursor::AbstractString
    match::AbstractString
    count::Int64
    function HashScanner(conn::RedisConnection, key::AbstractString, match::AbstractString, count::Int64)
        if keytype(conn, key) != "hash"
            throw(ProtocolException("Wrong key type: expected Hash; received $(keytype(conn, key))"))
        end
        new(conn, key, "0", match, count)
    end
end

function next!(HS::HashScanner; count=HS.count)
    HS.cursor, result = hscan(HS.conn, HS.key, parse(Int64, HS.cursor), "MATCH", HS.match, "COUNT", count)
    result
end

function collect(SS::StreamScanner)
    SS.cursor = "0"
    result = next!(SS)
    if typeof(SS) == HashScanner
        while SS.cursor != "0"
            for (key, val) in next!(SS)
                result[key] = val
            end
        end
        return result
    else
        while SS.cursor != "0"
            for item in next!(SS)
                push!(result, item)
            end
        end
    end
    collect(result)
end

"define a default callback that does nothing"
nullcb(args) = nothing

# Restricted to KeyScanner, SetScanner types
function collectAsync!(SS::StreamScanner, arr::Array{AbstractString, 1}; cb::Function=nullcb)
    if typeof(SS) == HashScanner || typeof(SS) == OrderedSetScanner
        throw(ProtocolException("inconsistent inputs: got $(typeof(arr)), should be Dict{AbstractString, AbstractString}"))
    end
    @async begin
        SS.cursor = "0"
        # start scan at cursor="0"
        for item in next!(SS)
            push!(arr, item)
        end
        while SS.cursor != "0"
            for item in next!(SS)
                push!(arr, item)
            end
        end
        cb(arr)
    end
end

# Restricted to OrderedSetScanner types
function collectAsync!(SS::StreamScanner, arr::Array{Tuple{Float64, AbstractString}, 1}; cb::Function=nullcb)
    if typeof(SS) != OrderedSetScanner
        throw(ProtocolException("inconsistent inputs: got $(typeof(arr)), should be Array{Tuple{Float64, AbstractString}, 1}"))
    end
    @async begin
        SS.cursor = "0"
        # start scan at cursor="0"
        for item in next!(SS)
            push!(arr, item)
        end
        while SS.cursor != "0"
            for item in next!(SS)
                push!(arr, item)
            end
        end
        cb(arr)
    end
end

# Restricted to a HashScanner type
function collectAsync!(HS::HashScanner, arr::Dict{AbstractString, AbstractString}; cb::Function=nullcb)
    if typeof(HS) != HashScanner
        throw(ProtocolException("inconsistent inputs: got $(typeof(HS)), should be HashScanner"))
    end
    @async begin
        HS.cursor = "0"
        # start scan at cursor="0"
        for (key, val) in next!(HS)
            arr[key] = val
        end
        while HS.cursor != "0"
            for (key, val) in next!(HS)
                arr[key] = val
            end
        end
        cb(arr)
    end
end
