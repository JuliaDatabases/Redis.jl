using Redis
using Base.Test

println("WARNING!\nRunning these tests will run flushall on localhost:6379\nPress enter to continue")
read(STDIN, Char)

conn = RedisConnection()
redis_flushall(conn)

############### Simple use for String/Key commands ###############
@test redis_set(conn, "testkey", "testvalue")
@test redis_get(conn, "testkey") == "testvalue"
@test redis_exists(conn, "testkey")
@test redis_keys(conn, "*") == Set({"testkey"})
@test redis_del(conn, "testkey", "nothing", "noway") == 1
@test redis_get(conn, "testkey") == nothing

@test redis_set(conn, "testkey", "testvalue")
@test redis_getrange(conn, "testkey", 0, 3) == "test"
@test redis_set(conn, "testkey", 2)
@test redis_incr(conn, "testkey") == 3
@test redis_incrby(conn, "testkey", 3) == 6
@test_approx_eq redis_incrbyfloat(conn, "testkey", 1.5) 7.5
@test redis_set(conn, "testkey2", "something")
@test Set(redis_mget(conn, "testkey", "testkey2")) == Set({"7.5", "something"})
@test redis_strlen(conn, "testkey2") == 9

############### Simple use for Hash commands ###############
@test redis_hmset(conn, "testhash", Dict({1 => 2, "3" => 4, "5" => "6"}))
@test redis_hget(conn, "testhash", 1) == "2"
@test Set(redis_hmget(conn, "testhash", 1, 3)) == Set({"2", "4"})
@test redis_hgetall(conn, "testhash") == Dict({"1" => "2", "3" => "4", "5" => "6"})
@test Set(redis_hvals(conn, "testhash")) == Set({"2", "4", "6"})

############### Transactions ###############
trans = redis_open_transaction(conn)
@test redis_set(trans, "testkey", "foobar") == "QUEUED"
@test redis_get(trans, "testkey") == "QUEUED"
@test redis_exec(trans) == ["OK", "foobar"]
disconnect(trans)

############### Pub/sub ###############
subs = redis_open_subscription(conn)
x = Any[]
f(y) = push!(x, y)
redis_subscribe(subs, "channel", f)
@test redis_publish(conn, "channel", "hello, world!") == 1
sleep(1)
@test x == ["hello, world!"]
disconnect(subs)

disconnect(conn)
