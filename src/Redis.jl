module Redis

export RedisException, ConnectionException, ServerException, ProtocolException, ClientException
export RedisConnection, SentinelConnection, TransactionConnection, SubscriptionConnection,
       disconnect, is_connected, redis_open_transaction, redis_reset_transaction, redis_open_subscription
# Key commands
export redis_del, redis_dump, redis_exists, redis_expire, redis_expireat, redis_keys,
       redis_migrate, redis_move, redis_persist, redis_pexpire, redis_pexpireat,
       redis_pttl, redis_randomkey, redis_rename, redis_renamenx, redis_restore,
       redis_scan, redis_sort, redis_ttl, redis_type
# String commands
export redis_append, redis_bitcount, redis_bitop, redis_bitpos, redis_decr, redis_decrby,
       redis_get, redis_getbit, redis_getrange, redis_getset, redis_incr, redis_incrby,
       redis_incrbyfloat, redis_mget, redis_mset, redis_msetnx, redis_psetex, redis_set,
       redis_setbit, redis_setex, redis_setnx, redis_setrange, redis_strlen
# Hash commands
export redis_hdel, redis_hexists, redis_hget, redis_hgetall, redis_hincrby, redis_hincrbyfloat,
       redis_hkeys, redis_hlen, redis_hmget, redis_hmset, redis_hset, redis_hsetnx, redis_hvals,
       redis_hscan
# List commands
export redis_blpop, redis_brpop, redis_brpoplpush, redis_lindex, redis_linsert, redis_llen,
       redis_lpop, redis_lpush, redis_lpushx, redis_lrange, redis_lrem, redis_lset,
       redis_ltrim, redis_rpop, redis_rpoplpush, redis_rpush, redis_rpushx
# Set commands
export redis_sadd, redis_scard, redis_sdiff, redis_sdiffstore, redis_sinter, redis_sinterstore,
       redis_sismember, redis_smembers, redis_smove, redis_spop, redis_srandmember, redis_srem,
       redis_sunion, redis_sunionstore, redis_sscan
# Sorted set commands
export redis_zadd, redis_zcard, redis_zcount, redis_zincrby, redis_zinterstore, redis_zlexcount,
       redis_zrange, redis_zrangebylex, redis_zrangebyscore, redis_zrank, redis_zrem,
       redis_zremrangebylex, redis_zremrangebyrank, redis_zremrangebyscore, redis_zrevrange,
       redis_zrevrangebyscore, redis_zrevrank, redis_zscore, redis_zunionstore, redis_zscan,
       Aggregate
# HyperLogLog commands
export redis_pfadd, redis_pfcount, redis_pfmerge
# Connection commands
export redis_auth, redis_echo, redis_ping, redis_quit, redis_select
# Transaction commands
export redis_discard, redis_exec, redis_multi, redis_unwatch, redis_watch
# Scripting commands
export redis_eval, redis_evalsha
# PubSub commands
export redis_subscribe, redis_publish, redis_psubscribe, redis_punsubscribe, redis_unsubscribe
# Server commands
export redis_bgrewriteaof, redis_bgsave, redis_command, redis_dbsize, redis_flushall,
       redis_flushdb, redis_info, redis_lastsave, redis_role, redis_save, redis_shutdown,
       redis_slaveof, redis_time
# Sentinel commands
export sentinel_masters, sentinel_master, sentinel_slaves, sentinel_getmasteraddrbyname,
       sentinel_reset, sentinel_failover, sentinel_monitor, sentinel_remove, sentinel_set

include("exceptions.jl")
include("parser.jl")
include("connection.jl")
include("client.jl")
include("commands.jl")

end
