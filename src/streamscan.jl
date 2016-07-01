#=
notes from http://redis.io/commands/scan:
    * The SCAN family of commands only offer limited guarantees about the returned elements since the collection
    that we incrementally iterate can change during the iteration process.
    * Basically with COUNT the user specified _the amount of work that should be done at every call in order to
      retrieve elements from the collection_. This is __just a hint__ for the implementation, however generally
      speaking this is what you could expect most of the times from the implementation.
=#
abstract StreamScanner

"""
        KeyScanner

Provides a convenient streaming interface for the Redis SCAN command.
"""
type KeyScanner <: StreamScanner
    conn::RedisConnection
    cursor::AbstractString
    match::AbstractString
    count::Int64
    KeyScanner(conn::RedisConnection, match::AbstractString, count::Int64) = new(conn, "0", match, count)
end

"retrieves the next `KeyScanner.count` items and returns an `Array`"
function next!(KS::KeyScanner; count=KS.count)
    KS.cursor, result = scan(KS.conn, parse(Int64, KS.cursor), "MATCH", KS.match, "COUNT", count)
    collect(result)
end

"""
        SetScanner

Provides a convenient streaming interface for the Redis SSCAN command.
"""
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

"retrieves the next `SetScanner.count` items and returns an `Array`"
function next!(SS::SetScanner; count=SS.count)
    SS.cursor, result = sscan(SS.conn, SS.key, parse(Int64, SS.cursor), "MATCH", SS.match, "COUNT", count)
    collect(result)
end

"""
        OrderedSetScanner

Provides a convenient streaming interface for the Redis ZSCAN command.
"""
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

"""
retrieves the next `OrderedSetScanner.count` items and returns a `Set` of Tuples(Float64, AbstractString)
where the first element represents the score and the second the value
"""
function next!(OS::OrderedSetScanner; count=OS.count)
    OS.cursor, response = zscan(OS.conn, OS.key, parse(Int64, OS.cursor), "MATCH", OS.match, "COUNT", count)
    r = OrderedSet{Tuple{Float64, AbstractString}}()
    for i=1:2:length(response)
        push!(r, (parse(Float64, response[i+1]), response[i]))
    end
    r
end

"""
        HashScanner

Provides a convenient streaming interface for the Redis ZSCAN command.
"""
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

"retrieves the next `HashScanner.count` items and returns a `Dict`"
function next!(HS::HashScanner; count=HS.count)
    HS.cursor, result = hscan(HS.conn, HS.key, parse(Int64, HS.cursor), "MATCH", HS.match, "COUNT", count)
    result
end

"retrieves all the items from a SCAN, SSCAN, ZSCAN or HSCAN command and returns an `Array`"
function Base.collect(SS::StreamScanner)
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

export KeyScanner, SetScanner, OrderedSetScanner, HashScanner, next!, collect
