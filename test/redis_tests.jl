using Redis
using Base.Test

println("WARNING!\nRunning these tests will run flushall on localhost:6379\nPress enter to continue")
read(STDIN, Char)

conn = RedisConnection()
flushall(conn)

############### Simple use for String/Key commands ###############
@test set(conn, "testkey", "testvalue")
@test get(conn, "testkey") == "testvalue"
@test exists(conn, "testkey")
@test Redis.keys(conn, "*") == Set({"testkey"})
@test del(conn, "testkey", "nothing", "noway") == 1
@test get(conn, "testkey") == nothing

@test set(conn, "testkey", "testvalue")
@test getrange(conn, "testkey", 0, 3) == "test"
@test set(conn, "testkey", 2)
@test incr(conn, "testkey") == 3
@test incrby(conn, "testkey", 3) == 6
@test_approx_eq incrbyfloat(conn, "testkey", 1.5) 7.5
@test set(conn, "testkey2", "something")
@test Set(mget(conn, "testkey", "testkey2")) == Set({"7.5", "something"})
@test strlen(conn, "testkey2") == 9

############### Simple use for Hash commands ###############
@test hmset(conn, "testhash", Dict({1 => 2, "3" => 4, "5" => "6"}))
@test hget(conn, "testhash", 1) == "2"
@test Set(hmget(conn, "testhash", 1, 3)) == Set({"2", "4"})
@test hgetall(conn, "testhash") == Dict({"1" => "2", "3" => "4", "5" => "6"})
@test Set(hvals(conn, "testhash")) == Set({"2", "4", "6"})

############### Transactions ###############
trans = open_transaction(conn)
@test set(trans, "testkey", "foobar") == "QUEUED"
@test get(trans, "testkey") == "QUEUED"
@test exec(trans) == ["OK", "foobar"]
disconnect(trans)

############### Pub/sub ###############
subs = open_subscription(conn)
x = Any[]
f(y) = push!(x, y)
subscribe(subs, "channel", f)
@test publish(conn, "channel", "hello, world!") == 1
sleep(1)
@test x == ["hello, world!"]
disconnect(subs)

disconnect(conn)
