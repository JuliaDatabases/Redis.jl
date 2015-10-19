const EXEC = ["exec"]

baremodule Aggregate
    const NotSet = ""
    const Sum = "sum"
    const Min = "min"
    const Max = "max"
end

# Key commands
@redisfunction "del" Integer key...
@redisfunction "dump" AbstractString key
@redisfunction "exists" Bool key
@redisfunction "expire" Bool key seconds::Integer
@redisfunction "expireat" Bool key timestamp::Integer
@redisfunction "keys" Set pattern
@redisfunction "migrate" Bool host port key destinationdb timeout
@redisfunction "move" Bool key db
@redisfunction "persist" Bool key
@redisfunction "pexpire" Bool key milliseconds::Integer
@redisfunction "pexpireat" Bool key millisecondstimestamp::Integer
@redisfunction "pttl" Integer key
@redisfunction "randomkey" AbstractString
@redisfunction "rename" AbstractString key newkey
@redisfunction "renamenx" Bool key newkey
@redisfunction "restore" Bool key ttl::Integer serializedvalue
@redisfunction "scan" Array cursor::Integer options...
@redisfunction "sort" Array key options...
@redisfunction "ttl" Integer key
function keytype(conn::RedisConnection, key)
    response = execute_command(conn, flatten_command("type", key))
    convert_response(AbstractString, response)
end
function keytype(conn::TransactionConnection, key)
    execute_command(conn, flatten_command("type", key))
end

# String commands
@redisfunction "append" Integer key value
@redisfunction "bitcount" Integer key options...
@redisfunction "bitop" Integer operation destkey key keys...
@redisfunction "bitpos" Integer key bit options...
@redisfunction "decr" Integer key
@redisfunction "decrby" Integer key decrement::Integer
@redisfunction "get" AbstractString key
@redisfunction "getbit" Integer key offset::Integer
@redisfunction "getrange" AbstractString key start::Integer finish::Integer
@redisfunction "getset" AbstractString key value
@redisfunction "incr" Integer key
@redisfunction "incrby" Integer key increment::Integer
@redisfunction "incrbyfloat" Float64 key increment::Float64
@redisfunction "mget" Array key keys...
@redisfunction "mset" Bool keyvalues::Dict{Any, Any}
@redisfunction "msetnx" Bool keyvalues::Dict{Any, Any}
@redisfunction "psetex" AbstractString key milliseconds::Integer value
@redisfunction "set" Bool key value options...
@redisfunction "setbit" Integer key offset::Integer value
@redisfunction "setex" AbstractString key seconds::Integer value
@redisfunction "setnx" Bool key value
@redisfunction "setrange" Integer key offset::Integer value
@redisfunction "strlen" Integer key

# Hash commands
@redisfunction "hdel" Integer key field fields...
@redisfunction "hexists" Bool key field
@redisfunction "hget" AbstractString key field
@redisfunction "hgetall" Dict key
@redisfunction "hincrby" Integer key field increment::Integer
@redisfunction "hincrbyfloat" Float64 key field increment::Float64
@redisfunction "hkeys" Array key
@redisfunction "hlen" Integer key
@redisfunction "hmget" Array key field fields...
@redisfunction "hmset" Bool key value::Dict{Any, Any}
@redisfunction "hset" Bool key field value
@redisfunction "hsetnx" Bool key field value
@redisfunction "hvals" Array key
@redisfunction "hscan" Array key cursor::Integer options...

# List commands
@redisfunction "blpop" AbstractString keys timeout::Integer
@redisfunction "brpop" AbstractString keys timeout::Integer
@redisfunction "brpoplpush" AbstractString source destination timeout::Integer
@redisfunction "lindex" AbstractString key index::Integer
@redisfunction "linsert" Integer key place pivot value
@redisfunction "llen" Integer key
@redisfunction "lpop" AbstractString key
@redisfunction "lpush" Integer key value values...
@redisfunction "lpushx" Integer key value
@redisfunction "lrange" Array key start::Integer finish::Integer
@redisfunction "lrem" Integer key count::Integer value
@redisfunction "lset" AbstractString key index::Integer value
@redisfunction "ltrim" AbstractString key start::Integer finish::Integer
@redisfunction "rpop" AbstractString key
@redisfunction "rpoplpush" AbstractString source destination
@redisfunction "rpush" integer key value values...
@redisfunction "rpushx" Integer key value

# Set commands
@redisfunction "sadd" Integer key member members...
@redisfunction "scard" Integer key
@redisfunction "sdiff" Set key keys...
@redisfunction "sdiffstore" Integer destination key keys...
@redisfunction "sinter" Set key keys...
@redisfunction "sinterstore" Integer destination key keys...
@redisfunction "sismember" Bool key member
@redisfunction "smembers" Set key
@redisfunction "smove" Bool source destination member
@redisfunction "spop" AbstractString key
@redisfunction "srandmember" AbstractString key
@redisfunction "srandmember" Set key count::Integer
@redisfunction "srem" Integer key member members...
@redisfunction "sunion" Set key keys...
@redisfunction "sunionstore" Integer destination key keys...
@redisfunction "sscan" Set key cursor::Integer options...

# Sorted set commands
@redisfunction "zadd" Integer key score::Number member
@redisfunction "zadd" Integer key scores::Dict{Number, Any}
@redisfunction "zcard" Integer key
@redisfunction "zcount" Integer key min::Number max::Number
@redisfunction "zincrby" AbstractString key increment::Number member
@redisfunction "zlexcount" Integer key min max
@redisfunction "zrange" Set key start::Integer finish::Integer options...
@redisfunction "zrangebylex" Set key min max options...
@redisfunction "zrangebyscore" Set key min::Number max::Number options...
@redisfunction "zrank" Integer key member
@redisfunction "zrem" Integer key member members...
@redisfunction "zremrangebylex" Integer key min max
@redisfunction "zremrangebyrank" Integer key start::Integer finish::Integer
@redisfunction "zremrangebyscore" Integer key start::Number finish::Number
@redisfunction "zrevrange" Set key start::Integer finish::Integer options...
@redisfunction "zrevrangebyscore" Set key start::Number finish::Number options...
@redisfunction "zrevrank" Integer key member
@redisfunction "zscore" Float64 key member
@redisfunction "zscan" Set key cursor::Integer options...

function _build_store_internal(destination, numkeys, keys, weights, aggregate, command)
    length(keys) > 0 || throw(ClientException("Must supply at least one key"))
    suffix = []
    if length(weights) > 0
        suffix = map(string, weights)
        unshift!(suffix, "weights")
    end
    if aggregate != Aggregate.NotSet
        push!(suffix, "aggregate")
        push!(suffix, aggregate)
    end
    vcat([command, destination, numkeys], keys, suffix)
end

function zinterstore(conn::RedisConnectionBase, destination, numkeys::Integer,
    keys::Array, weights=[], aggregate=Aggregate.NotSet)
    command = _build_store_internal(destination, nunkeys, keys, weights, aggregate, "zinterstore")
    execute_command(conn, command)
end

function zunionstore(conn::RedisConnectionBase, destination, numkeys::Integer,
    keys::Array, weights=[], aggregate=Aggregate.NotSet)
    command = _build_store_internal(destination, nunkeys, keys, weights, aggregate, "zunionstore")
    execute_command(conn, command)
end

# HyperLogLog commands
@redisfunction "pfadd" Bool key element elements...
@redisfunction "pfcount" Integer key keys...
@redisfunction "pfmerge" Bool destkey sourcekey sourcekeys...

# Connection commands
@redisfunction "auth" AbstractString password
@redisfunction "echo" AbstractString message
@redisfunction "ping" AbstractString
@redisfunction "quit" Bool
@redisfunction "select" AbstractString index::Integer

# Transaction commands
@redisfunction "discard" Bool
@redisfunction "exec" Array
@redisfunction "multi" Bool
@redisfunction "unwatch" Bool
@redisfunction "watch" Bool key keys...

# Scripting commands
function evalscript(conn::RedisConnection, script, numkeys::Integer, args)
    response = execute_command(conn, flatten_command("eval", script, numkeys, args))
    convert_response(Any, response)
end
function evalscript(conn::RedisConnection, script, numkeys::Integer, args)
    execute_command(conn, flatten_command("eval", script, numkeys, args))
end
@redisfunction "evalsha" Any sha1 numkeys::Integer keys args
@redisfunction "script_exists" Array script scripts...
@redisfunction "script_flush" AbstractString
@redisfunction "script_kill" AbstractString
@redisfunction "script_load" AbstractString script

# Server commands
@redisfunction "bgrewriteaof" Bool
@redisfunction "bgsave" AbstractString
@redisfunction "client_getname" AbstractString
@redisfunction "client_list" AbstractString
@redisfunction "client_pause" Bool timeout::Integer
@redisfunction "client_setname" Bool name
@redisfunction "cluster_slots" Array
@redisfunction "command" Array
@redisfunction "command_count" Integer
@redisfunction "command_info" Array command commands...
@redisfunction "config_get" Array parameter
@redisfunction "config_resetstat" Bool
@redisfunction "config_rewrite" Bool
@redisfunction "config_set" Bool parameter value
@redisfunction "dbsize" Integer
@redisfunction "debug_object" AbstractString key
@redisfunction "debug_segfault" Any
@redisfunction "flushall" AbstractString
@redisfunction "flushdb" AbstractString
@redisfunction "info" AbstractString
@redisfunction "info" AbstractString section
@redisfunction "lastsave" Integer
@redisfunction "role" Array
@redisfunction "save" Bool
@redisfunction "shutdown" AbstractString
@redisfunction "shutdown" AbstractString option
@redisfunction "slaveof" AbstractString host port
@redisfunction "_time" Array

# Sentinel commands
@sentinelfunction "master" Dict mastername
@sentinelfunction "reset" Integer pattern
@sentinelfunction "failover" Any mastername
@sentinelfunction "monitor" Bool name ip port quorum
@sentinelfunction "remove" Bool name
@sentinelfunction "set" Bool name option value

function sentinel_masters(conn::SentinelConnection)
    response = execute_command(conn, flatten_command("sentinel", "masters"))
    [convert_response(Dict, master) for master in response]
end

function sentinel_slaves(conn::SentinelConnection, mastername)
    response = execute_command(conn, flatten_command("sentinel", "slaves", mastername))
    [convert_response(Dict, slave) for slave in response]
end

function sentinel_getmasteraddrbyname(conn::SentinelConnection, mastername)
    execute_command(conn, flatten_command("sentinel", "get-master-addr-by-name", mastername))
end

# Custom commands (PubSub/Transaction)
@redisfunction "publish" Integer channel message

function _subscribe(conn::SubscriptionConnection, channels::Array)
    execute_command(conn, unshift!(channels, "subscribe"))
end

function subscribe(conn::SubscriptionConnection, channel::AbstractString, callback::Function)
    conn.callbacks[channel] = callback
    _subscribe(conn, [channel])
end

function subscribe(conn::SubscriptionConnection, subs::Dict{AbstractString, Function})
    for (channel, callback) in subs
        conn.callbacks[channel] = callback
    end
    _subscribe(conn, collect(keys(subs)))
end

function unsubscribe(conn::SubscriptionConnection, channels...)
    for channel in channels
        delete!(conn.callbacks, channel)
    end
    execute_command(conn, unshift!(channels, "unsubscribe"))
end

function _psubscribe(conn::SubscriptionConnection, patterns::Array)
    execute_command(conn, unshift!(patterns, "psubscribe"))
end

function psubscribe(conn::SubscriptionConnection, pattern::AbstractString, callback::Function)
    conn.callbacks[pattern] = callback
    _psubscribe(conn, [pattern])
end

function psubscribe(conn::SubscriptionConnection, subs::Dict{AbstractString, Function})
    for (pattern, callback) in subs
        conn.callbacks[pattern] = callback
    end
    _psubscribe(conn, collect(values(subs)))
end

function punsubscribe(conn::SubscriptionConnection, patterns...)
    for pattern in patterns
        delete!(conn.pcallbacks, pattern)
    end
    execute_command(conn, unshift!(patterns, "punsubscribe"))
end

# Need a specialized version of execute to keep the connection in the transaction state
function exec(conn::TransactionConnection)
    response = execute_command(conn, EXEC)
    multi(conn)
    response
end

###############################################################
# The following Redis commands can be typecast to Julia structs
###############################################################

function time(c::RedisConnection)
    t = _time(c)
    s = parse(Int,t[1])
    ms = parse(Float64, t[2])
    s += (ms / 1e6)
    return unix2datetime(s)
end
