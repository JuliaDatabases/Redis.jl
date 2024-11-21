module Redis
using Dates
using Sockets
using MbedTLS

import Base.get, Base.keys, Base.time

export RedisException, ConnectionException, ServerException, ProtocolException, ClientException
export RedisConnection, SentinelConnection, TransactionConnection, SubscriptionConnection,
disconnect, is_connected, open_transaction, reset_transaction, open_subscription,
open_pipeline, read_pipeline
# Key commands
export del, dump, exists, expire, expireat, keys,
       migrate, move, persist, pexpire, pexpireat,
       pttl, randomkey, rename, renamenx, restore,
       scan, sort, ttl, keytype
# String commands
export append, bitcount, bitop, bitpos, decr, decrby,
       get, getbit, getrange, getset, incr, incrby,
       incrbyfloat, mget, mset, msetnx, psetex, set,
       setbit, setex, setnx, setrange, strlen
# Hash commands
export hdel, hexists, hget, hgetall, hincrby, hincrbyfloat,
       hkeys, hlen, hmget, hmset, hset, hsetnx, hvals,
       hscan
# List commands
export blpop, brpop, brpoplpush, lindex, linsert, llen,
       lpop, lpush, lpushx, lrange, lrem, lset,
       ltrim, rpop, rpoplpush, rpush, rpushx
# Set commands
export sadd, scard, sdiff, sdiffstore, sinter, sinterstore,
       sismember, smembers, smove, spop, srandmember, srem,
       sunion, sunionstore, sscan
# Sorted set commands
export zadd, zcard, zcount, zincrby, zinterstore, zlexcount,
       zrange, zrangebylex, zrangebyscore, zrank, zrem,
       zremrangebylex, zremrangebyrank, zremrangebyscore, zrevrange,
       zrevrangebyscore, zrevrank, zscore, zunionstore, zscan, bzpopmin,
       Aggregate
# HyperLogLog commands
export pfadd, pfcount, pfmerge
# Connection commands
export auth, echo, ping, quit, select
# Transaction commands
export discard, exec, multi, unwatch, watch
# Scripting commands
export evalscript, evalsha, script_exists, script_flush, script_kill, script_load
# PubSub commands
export subscribe, subscribe_data, publish, psubscribe, psubscribe_data, punsubscribe, unsubscribe
# Server commands
export bgrewriteaof, bgsave, client_list, client_id, client_pause, client_setname, cluster_slots,
       command, command_count, command_info, config_get, config_resetstat, config_rewrite,
       config_set, dbsize, debug_object, debug_segfault, flushall, flushdb, info, lastsave,
       role, save, shutdown, slaveof, time
# Sentinel commands
export sentinel_masters, sentinel_master, sentinel_slaves, sentinel_getmasteraddrbyname,
       sentinel_reset, sentinel_failover, sentinel_monitor, sentinel_remove, sentinel_set
# Redis constants
# TODO: add more, consider puuting these in separate constants.jl
export REDIS_PERSISTENT_KEY, REDIS_EXPIRED_KEY

include("exceptions.jl")
include("transport/transport.jl")
include("connection.jl")
include("parser.jl")
include("client.jl")
include("commands.jl")

end
