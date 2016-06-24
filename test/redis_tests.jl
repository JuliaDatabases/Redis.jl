using Redis
using Base.Test

println("WARNING!\nRunning these tests will flush db 0 on localhost:6379\nPress enter to continue")
read(STDIN, Char)

conn = RedisConnection(db=0)
flushdb(conn)

############### Simple use for String/Key commands ###############
@test set(conn, "testkey", "testvalue")
@test get(conn, "testkey") == "testvalue"
@test exists(conn, "testkey")
@test keys(conn, "*") == Set(["testkey"])
@test del(conn, "testkey", "nothing", "noway") == 1
@test get(conn, "testkey") == nothing

@test set(conn, "testkey", "testvalue")
@test getrange(conn, "testkey", 0, 3) == "test"
@test set(conn, "testkey", 2)
@test incr(conn, "testkey") == 3
@test incrby(conn, "testkey", 3) == 6
@test_approx_eq incrbyfloat(conn, "testkey", 1.5) 7.5
@test set(conn, "testkey2", "something")
@test Set(mget(conn, "testkey", "testkey2")) == Set(["7.5", "something"])
@test strlen(conn, "testkey2") == 9

############### Simple use for Hash commands ###############
@test hmset(conn, "testhash", Dict(1 => 2, "3" => 4, "5" => "6"))
@test hget(conn, "testhash", 1) == "2"
@test Set(hmget(conn, "testhash", 1, 3)) == Set(["2", "4"])
@test hgetall(conn, "testhash") == Dict("1" => "2", "3" => "4", "5" => "6")
@test Set(hvals(conn, "testhash")) == Set(["2", "4", "6"])

############### Simple use for *scan commands ###############
flushdb(conn)

for i in 1:100 sadd(conn, "testset", "testitem$i") end
cursor, values = sscan(conn, "testset", 0)
cursor::Integer
values::Set

cursor, values = scan(conn, 0)
@test cursor == 0
@test values == ["testset"]

hmset(conn, "testhash", Dict(1 => 2, "3" => 4, "5" => "6"))
cursor, values = hscan(conn, "testhash", 0)
@test cursor == 0
@test values == Dict("1" => "2", "3" => "4", "5" => "6")

for i in 1:100 zadd(conn, "testzset", 100-i, "testitem$i") end
cursor, values = zscan(conn, "testzset", 0, :count, 100)
@test cursor == 0
@test issorted(values, lt=(x,y)->x[2]<y[2])

############### Transactions ###############
trans = open_transaction(conn)
@test set(trans, "testkey", "foobar") == "QUEUED"
@test get(trans, "testkey") == "QUEUED"
@test exec(trans) == ["OK", "foobar"]
disconnect(trans)

############## Pipelining #############
pipe = open_pipeline(conn)
set(pipe, "pipeline", "anything")
@test length(read_pipeline(pipe)) == 1
get(pipe, "pipeline")
set(pipe, "another", "testing")
result = read_pipeline(pipe)
@test length(result) == 2
@test result == ["anything", "OK"]
disconnect(pipe)

############### Pub/sub ###############
g(y) = print(y)
subs = open_subscription(conn, g)
x = Any[]
f(y) = push!(x, y)
subscribe(subs, "channel", f)
subscribe(subs, "duplicate", f)
@test publish(conn, "channel", "hello, world!") == 1
sleep(2)
@test x == ["hello, world!"]
disconnect(subs)

disconnect(conn)
