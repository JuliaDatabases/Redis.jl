import DataStructures.OrderedSet

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
@redisfunction "expire" Bool key seconds
@redisfunction "expireat" Bool key timestamp
@redisfunction "keys" Set{AbstractString} pattern
@redisfunction "migrate" Bool host port key destinationdb timeout
@redisfunction "move" Bool key db
@redisfunction "persist" Bool key
@redisfunction "pexpire" Bool key milliseconds
@redisfunction "pexpireat" Bool key millisecondstimestamp
@redisfunction "pttl" Integer key
@redisfunction "randomkey" Nullable{AbstractString}
@redisfunction "rename" AbstractString key newkey
@redisfunction "renamenx" Bool key newkey
@redisfunction "restore" Bool key ttl serializedvalue
@redisfunction "scan" Array{AbstractString, 1} cursor::Integer options...
@redisfunction "sort" Array{AbstractString, 1} key options...
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
@redisfunction "decrby" Integer key decrement
@redisfunction "get" Nullable{AbstractString} key
@redisfunction "getbit" Integer key offset
@redisfunction "getrange" AbstractString key start finish
@redisfunction "getset" AbstractString key value
@redisfunction "incr" Integer key
@redisfunction "incrby" Integer key increment::Integer

# Bulk string reply: the value of key after the increment,
# as per http://redis.io/commands/incrbyfloat
@redisfunction "incrbyfloat" AbstractString key increment::Float64
@redisfunction "mget" Array{Nullable{AbstractString}, 1} key keys...
@redisfunction "mset" Bool keyvalues
@redisfunction "msetnx" Bool keyvalues
@redisfunction "psetex" AbstractString key milliseconds value
@redisfunction "set" Bool key value options...
@redisfunction "setbit" Integer key offset value
@redisfunction "setex" AbstractString key seconds value
@redisfunction "setnx" Bool key value
@redisfunction "setrange" Integer key offset value
@redisfunction "strlen" Integer key

# Hash commands
@redisfunction "hdel" Integer key field fields...
@redisfunction "hexists" Bool key field
@redisfunction "hget" Nullable{AbstractString} key field
@redisfunction "hgetall" Dict{AbstractString, AbstractString} key
@redisfunction "hincrby" Integer key field increment::Integer

# Bulk string reply: the value of key after the increment,
# as per http://redis.io/commands/hincrbyfloat
@redisfunction "hincrbyfloat" AbstractString key field increment::Float64

@redisfunction "hkeys" Array{AbstractString, 1} key
@redisfunction "hlen" Integer key
@redisfunction "hmget" Array{Nullable{AbstractString}, 1} key field fields...
@redisfunction "hmset" Bool key value
@redisfunction "hset" Bool key field value
@redisfunction "hsetnx" Bool key field value
@redisfunction "hvals" Array{AbstractString, 1} key
@redisfunction "hscan" Array key cursor::Integer options...

# List commands
@redisfunction "blpop" Array{AbstractString, 1} keys timeout
@redisfunction "brpop" Array{AbstractString, 1} keys timeout
@redisfunction "brpoplpush" AbstractString source destination timeout
@redisfunction "lindex" Nullable{AbstractString} key index
@redisfunction "linsert" Integer key place pivot value
@redisfunction "llen" Integer key
@redisfunction "lpop" Nullable{AbstractString} key
@redisfunction "lpush" Integer key value values...
@redisfunction "lpushx" Integer key value
@redisfunction "lrange" Array{AbstractString, 1} key start finish
@redisfunction "lrem" Integer key count value
@redisfunction "lset" AbstractString key index value
@redisfunction "ltrim" AbstractString key start finish
@redisfunction "rpop" Nullable{AbstractString} key
@redisfunction "rpoplpush" Nullable{AbstractString} source destination
@redisfunction "rpush" Integer key value values...
@redisfunction "rpushx" Integer key value

# Set commands
@redisfunction "sadd" Integer key member members...
@redisfunction "scard" Integer key
@redisfunction "sdiff" Set{AbstractString} key keys...
@redisfunction "sdiffstore" Integer destination key keys...
@redisfunction "sinter" Set{AbstractString} key keys...
@redisfunction "sinterstore" Integer destination key keys...
@redisfunction "sismember" Bool key member
@redisfunction "smembers" Set{AbstractString} key
@redisfunction "smove" Bool source destination member
@redisfunction "spop" Nullable{AbstractString} key
@redisfunction "srandmember" Nullable{AbstractString} key
@redisfunction "srandmember" Set{AbstractString} key count
@redisfunction "srem" Integer key member members...
@redisfunction "sunion" Set{AbstractString} key keys...
@redisfunction "sunionstore" Integer destination key keys...
@redisfunction "sscan" Set{AbstractString} key cursor::Integer options...

# Sorted set commands
#=
merl-dev: a number of methods were added to take AbstractString for score value
to enable score ranges like '(1 2,' or "-inf", "+inf",
as per docs http://redis.io/commands/zrangebyscore
=#

@redisfunction "zadd" Integer key score::Number member::AbstractString

# NOTE:  using ZADD with Dicts could introduce bugs if some scores are identical
@redisfunction "zadd" Integer key scorememberdict

#=
This following version of ZADD enables adding new members using `Tuple{Int64, AbstractString}` or
`Tuple{Float64, AbstractString}` for single or multiple additions to the sorted set without
resorting to the use of `Dict`, which cannot be used in the case where all entries have the same score.
=#
@redisfunction "zadd" Integer key scoremembertup scorememberstup...

@redisfunction "zcard" Integer key
@redisfunction "zcount" Integer key min max

# Bulk string reply: the new score of member (a double precision floating point number),
# represented as string, as per http://redis.io/commands/zincrby
@redisfunction "zincrby" AbstractString key increment member

@redisfunction "zlexcount" Integer key min max
@redisfunction "zrange" OrderedSet{AbstractString} key start finish options...
@redisfunction "zrangebylex" OrderedSet{AbstractString} key min max options...
@redisfunction "zrangebyscore" OrderedSet{AbstractString} key min max options...
@redisfunction "zrank" Nullable{Integer} key member
@redisfunction "zrem" Integer key member members...
@redisfunction "zremrangebylex" Integer key min max
@redisfunction "zremrangebyrank" Integer key start finish
@redisfunction "zremrangebyscore" Integer key start finish
@redisfunction "zrevrange" OrderedSet{AbstractString} key start finish options...
@redisfunction "zrevrangebyscore" OrderedSet{AbstractString} key start finish options...
@redisfunction "zrevrank" Nullable{Integer} key member
# ZCORE returns a Bulk string reply: the score of member (a double precision floating point
# number), represented as string.
@redisfunction "zscore" Nullable{AbstractString} key member
@redisfunction "zscan" Set{AbstractString} key cursor::Integer options...

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

# TODO: PipelineConnection and TransactionConnection
function zinterstore(conn::RedisConnectionBase, destination, numkeys,
    keys::Array, weights=[]; aggregate=Aggregate.NotSet)
    command = _build_store_internal(destination, numkeys, keys, weights, aggregate, "zinterstore")
    execute_command(conn, command)
end

function zunionstore(conn::RedisConnectionBase, destination, numkeys::Integer,
    keys::Array, weights=[]; aggregate=Aggregate.NotSet)
    command = _build_store_internal(destination, numkeys, keys, weights, aggregate, "zunionstore")
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
@redisfunction "select" AbstractString index

# Transaction commands
@redisfunction "discard" Bool
@redisfunction "exec" Array{Bool} # only one element ever in this array?
@redisfunction "multi" Bool
@redisfunction "unwatch" Bool
@redisfunction "watch" Bool key keys...

# Scripting commands
# TODO: PipelineConnection and TransactionConnection
function evalscript(conn::RedisConnection, script, numkeys::Integer, args)
    response = execute_command(conn, flatten_command("eval", script, numkeys, args))
    convert_eval_response(Any, response)
end

#################################################################
# TODO: NEED TO TEST BEYOND THIS POINT
@redisfunction "evalsha" Any sha1 numkeys keys args
@redisfunction "script_exists" Array script scripts...
@redisfunction "script_flush" AbstractString
@redisfunction "script_kill" AbstractString
@redisfunction "script_load" AbstractString script

# Server commands
@redisfunction "bgrewriteaof" Bool
@redisfunction "bgsave" AbstractString
@redisfunction "client_getname" AbstractString
@redisfunction "client_list" AbstractString
@redisfunction "client_pause" Bool timeout
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
@redisfunction "flushdb" AbstractString Integer
@redisfunction "info" AbstractString
@redisfunction "info" AbstractString section
@redisfunction "lastsave" Integer
@redisfunction "role" Array
@redisfunction "save" Bool
@redisfunction "shutdown" AbstractString
@redisfunction "shutdown" AbstractString option
@redisfunction "slaveof" AbstractString host port
@redisfunction "_time" Array{AbstractString, 1}

# Sentinel commands
@sentinelfunction "master" Dict{AbstractString, AbstractString} mastername
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
    execute_command_without_reply(conn, unshift!(channels, "subscribe"))
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
    execute_command_without_reply(conn, unshift!(patterns, "psubscribe"))
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

#Need a specialized version of execute to keep the connection in the transaction state
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
