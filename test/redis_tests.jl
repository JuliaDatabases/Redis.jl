using Redis
using Base.Test

println("WARNING!\nRunning these tests will NOT flushall on localhost:6379, nor leave any traces
unless some of the tests fail. In that case, test key strings are all prefixed by 'Redis_Test_'
and can be safely deleted.")

conn = RedisConnection()
# create some random string keys in case we want to run this on our own Redis instance
testkey = "Redis_Test_"*randstring()
testkey2 = "Redis_Test_"*randstring()
testkey3 = "Redis_Test_"*randstring()
testkey4 = "Redis_Test_"*randstring()
testhash = "Redis_Test_"*randstring()

############### Simple use for String/Key commands ###############
@test set(conn, testkey, "testvalue")
@test get(conn, testkey) == "testvalue"
@test exists(conn, testkey)
@test keys(conn, testkey) == Set([testkey])
@test del(conn, testkey, "nothing", "noway") == 1
@test get(conn, testkey) == nothing

@test set(conn, testkey, "testvalue")
@test getrange(conn, testkey, 0, 3) == "test"
@test set(conn, testkey, 2)
@test incr(conn, testkey) == 3
@test incrby(conn, testkey, 3) == 6
@test_approx_eq incrbyfloat(conn, testkey, 1.5) 7.5
@test set(conn, testkey2, "something")
@test Set(mget(conn, testkey, testkey2)) == Set(["7.5", "something"])
@test strlen(conn, testkey2) == 9
@test del(conn, testkey2) == true


############### Simple use for Hash commands ###############
@test hmset(conn, testhash, Dict(1 => 2, "3" => 4, "5" => "6"))
@test hget(conn, testhash, 1) == "2"
@test Set(hmget(conn, testhash, 1, 3)) == Set(["2", "4"])
@test hgetall(conn, testhash) == Dict("1" => "2", "3" => "4", "5" => "6")
@test Set(hvals(conn, testhash)) == Set(["2", "4", "6"])
@test del(conn, testhash) == true

############### Transactions ###############
trans = open_transaction(conn)
@test set(trans, testkey, "foobar") == "QUEUED"
@test get(trans, testkey) == "QUEUED"
@test exec(trans) == ["OK", "foobar"]
@test del(trans, testkey) == "QUEUED"
@test exec(trans) == Any[true]
disconnect(trans)

############## Pipelining #############
pipe = open_pipeline(conn)
set(pipe, testkey3, "anything")
@test length(read_pipeline(pipe)) == 1
get(pipe, testkey3)
set(pipe, testkey4, "testing")
result = read_pipeline(pipe)
@test length(result) == 2
@test result == ["anything", "OK"]
@test del(pipe, testkey3) == 1
@test del(pipe, testkey4) == 2
@test result ==  ["anything","OK"]
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
# following command prints ("Invalid response received: ")
disconnect(subs)

disconnect(conn)
