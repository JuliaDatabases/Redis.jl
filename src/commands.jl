const EXEC = ["exec"]

baremodule Aggregate
    const NotSet = ""
    const Sum = "sum"
    const Min = "min"
    const Max = "max"
end

# Key commands
@redisfunction "del" Integer key...
@redisfunction "dump" String key
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
@redisfunction "randomkey" String
@redisfunction "rename" String key newkey
@redisfunction "renamenx" Bool key newkey
@redisfunction "restore" Bool key ttl::Integer serializedvalue
@redisfunction "scan" Array cursor::Integer options...
@redisfunction "sort" Array key options...
@redisfunction "ttl" Integer key
@redisfunction "type" String key

# String commands
@redisfunction "append" Integer key value
@redisfunction "bitcount" Integer key options...
@redisfunction "bitop" Integer operation destkey key keys...
@redisfunction "bitpos" Integer key bit options...
@redisfunction "decr" Integer key
@redisfunction "decrby" Integer key decrement::Integer
@redisfunction "get" String key
@redisfunction "getbit" Integer key offset::Integer
@redisfunction "getrange" String key start::Integer finish::Integer
@redisfunction "getset" String key value
@redisfunction "incr" Integer key
@redisfunction "incrby" Integer key increment::Integer
@redisfunction "incrbyfloat" Float64 key increment::Float64
@redisfunction "mget" Array key keys...
@redisfunction "mset" Bool keyvalues::Dict{Any, Any}
@redisfunction "msetnx" Bool keyvalues::Dict{Any, Any}
@redisfunction "psetex" String key milliseconds::Integer value
@redisfunction "set" Bool key value options...
@redisfunction "setbit" Integer key offset::Integer value
@redisfunction "setex" String key seconds::Integer value
@redisfunction "setnx" Bool key value
@redisfunction "setrange" Integer key offset::Integer value
@redisfunction "strlen" Integer key

# Hash commands
@redisfunction "hdel" Integer key field fields...
@redisfunction "hexists" Bool key field
@redisfunction "hget" String key field
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
@redisfunction "blpop" String keys timeout::Integer
@redisfunction "brpop" String keys timeout::Integer
@redisfunction "brpoplpush" String source destination timeout::Integer
@redisfunction "lindex" String key index::Integer
@redisfunction "linsert" Integer key place pivot value
@redisfunction "llen" Integer key
@redisfunction "lpop" String key
@redisfunction "lpush" Integer key value values...
@redisfunction "lpushx" Integer key value
@redisfunction "lrange" Array key start::Integer finish::Integer
@redisfunction "lrem" Integer key count::Integer value
@redisfunction "lset" String key index::Integer value
@redisfunction "ltrim" String key start::Integer finish::Integer
@redisfunction "rpop" String key
@redisfunction "rpoplpush" String source destination
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
@redisfunction "spop" String key
@redisfunction "srandmember" String key
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
@redisfunction "zincrby" String key increment::Number member
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

function redis_zinterstore(conn::RedisConnectionBase, destination, numkeys::Integer,
    keys::Array, weights=[], aggregate=Aggregate.NotSet)
    command = _build_store_internal(destination, nunkeys, keys, weights, aggregate, "zinterstore")
    execute_redis_command(conn, command)
end

function redis_zunionstore(conn::RedisConnectionBase, destination, numkeys::Integer,
    keys::Array, weights=[], aggregate=Aggregate.NotSet)
    command = _build_store_internal(destination, nunkeys, keys, weights, aggregate, "zunionstore")
    execute_redis_command(conn, command)
end

# HyperLogLog commands
@redisfunction "pfadd" Bool key element elements...
@redisfunction "pfcount" Integer key keys...
@redisfunction "pfmerge" Bool destkey sourcekey sourcekeys...

# Connection commands
@redisfunction "auth" String password
@redisfunction "echo" String message
@redisfunction "ping" String
@redisfunction "quit" Bool
@redisfunction "select" String index::Integer

# Transaction commands
@redisfunction "discard" Bool
@redisfunction "exec" Array
@redisfunction "multi" Bool
@redisfunction "unwatch" Bool
@redisfunction "watch" Bool key keys...

# Scripting commands
# TODO: compound commands
@redisfunction "eval" Any script numkeys::Integer keys args
@redisfunction "evalsha" Any sha1 numkeys::Integer keys args

# Server commands
# TODO: compound commands
@redisfunction "bgrewriteaof" Bool
@redisfunction "bgsave" String
@redisfunction "command" Array
@redisfunction "dbsize" Integer
@redisfunction "flushall" String
@redisfunction "flushdb" String
@redisfunction "info" String
@redisfunction "info" String section
@redisfunction "lastsave" Integer
@redisfunction "role" Array
@redisfunction "save" Bool
@redisfunction "shutdown" String
@redisfunction "shutdown" String option
@redisfunction "slaveof" String host port
@redisfunction "time" Array

# Sentinel commands
@sentinelfunction "master" Dict mastername
@sentinelfunction "reset" Integer pattern
@sentinelfunction "failover" Any mastername
@sentinelfunction "monitor" Bool name ip port quorum
@sentinelfunction "remove" Bool name
@sentinelfunction "set" Bool name option value

function sentinel_masters(conn::SentinelConnection)
    response = execute_redis_command(conn, flatten_command("sentinel", "masters"))
    [convert_redis_response(Dict, master) for master in response]
end

function sentinel_slaves(conn::SentinelConnection, mastername)
    response = execute_redis_command(conn, flatten_command("sentinel", "slaves", mastername))
    [convert_redis_response(Dict, slave) for slave in response]
end

function sentinel_getmasteraddrbyname(conn::SentinelConnection, mastername)
    execute_redis_command(conn, flatten_command("sentinel", "get-master-addr-by-name", mastername))
end

# Custom commands (PubSub/Transaction)
@redisfunction "publish" Integer channel message

function _redis_subscribe(conn::SubscriptionConnection, channels::Array)
    execute_redis_command(conn, unshift!(channels, "subscribe"))
end

function redis_subscribe(conn::SubscriptionConnection, channel::String, callback::Function)
    conn.callbacks[channel] = callback
    _redis_subscribe(conn, [channel])
end

function redis_subscribe(conn::SubscriptionConnection, subs::Dict{String, Function})
    for (channel, callback) in subs
        conn.callbacks[channel] = callback
    end
    _redis_subscribe(conn, collect(keys(subs)))
end

function redis_unsubscribe(conn::SubscriptionConnection, channels...)
    for channel in channels
        delete!(conn.callbacks, channel)
    end
    execute_redis_command(conn, unshift!(channels, "unsubscribe"))
end

function _redis_psubscribe(conn::SubscriptionConnection, patterns::Array)
    execute_redis_command(conn, unshift!(patterns, "psubscribe"))
end

function redis_psubscribe(conn::SubscriptionConnection, pattern::String, callback::Function)
    conn.callbacks[pattern] = callback
    _redis_psubscribe(conn, [pattern])
end

function redis_psubscribe(conn::SubscriptionConnection, subs::Dict{String, Function})
    for (pattern, callback) in subs
        conn.callbacks[pattern] = callback
    end
    _redis_psubscribe(conn, collect(values(subs)))
end

function redis_punsubscribe(conn::SubscriptionConnection, patterns...)
    for pattern in patterns
        delete!(conn.pcallbacks, pattern)
    end
    execute_redis_command(conn, unshift!(patterns, "punsubscribe"))
end

# Need a specialized version of execute to keep the connection in the transaction state
function redis_exec(conn::TransactionConnection)
    response = execute_redis_command(conn, EXEC)
    redis_multi(conn)
    response
end
