
# constants for code legibility
const REDIS_PERSISTENT_KEY =  -1
const REDIS_EXPIRED_KEY =  -2

# some random key names
testkey = "Redis_Test_"*randstring()
testkey2 = "Redis_Test_"*randstring()
testkey3 = "Redis_Test_"*randstring()
testkey4 = "Redis_Test_"*randstring()
testhash = "Redis_Test_"*randstring()

# some random strings
s1 = randstring(); s2 = randstring(); s3 = randstring()
s4 = randstring(); s5 = randstring(); s6 = randstring()
s7 = randstring(); s8 = randstring(); s9 = randstring()

function redis_tests(conn = RedisConnection())
    flushall(conn)

    @testset "Strings" begin
        @test set(conn, testkey, s1)
        @test get(conn, testkey) == s1
        @test exists(conn, testkey)
        @test keys(conn, testkey) == Set([testkey])
        @test del(conn, testkey, "notakey", "notakey2") == 1  # only 1 of 3 key exists

        # 'NIL'
        @test get(conn, "notakey") === nothing

        set(conn, testkey, s1)
        set(conn, testkey2, s2)
        set(conn, testkey3, s3)
        # RANDOMKEY can return 'NIL', so it returns Union{Nothing, T}.  KEYS * always returns empty Set when Redis is empty
        @test randomkey(conn) in keys(conn, "*")
        @test getrange(conn, testkey, 0, 3) == s1[1:4]

        @test set(conn, testkey, 2)
        @test incr(conn, testkey) == 3
        @test incrby(conn, testkey, 3) == 6
        @test incrbyfloat(conn, testkey, 1.5) == "7.5"
        @test mget(conn, testkey, testkey2, testkey3) == ["7.5", s2, s3]
        @test strlen(conn, testkey2) == length(s2)
        @test rename(conn, testkey2, testkey4) == "OK"
        @test testkey4 in keys(conn,"*")
        del(conn, testkey, testkey2, testkey3, testkey4)

        @test append(conn, testkey, s1) == length(s1)
        @test append(conn, testkey, s2) == length(s1) + length(s2)
        get(conn, testkey) == string(s1, s2)
        del(conn, testkey)
    end

    @testset "Bits" begin
        @test setbit(conn,testkey, 0, 1) == 0
        @test setbit(conn,testkey, 2, 1) == 0
        @test getbit(conn, testkey, 0) == 1
        @test getbit(conn, testkey, 1) == 0  # default is 0
        @test getbit(conn, testkey, 2) == 1
        @test bitcount(conn, testkey) == 2
        del(conn, testkey)

        for i=0:3
            setbit(conn, testkey, i, 1)
            setbit(conn, testkey2, i, 1)
        end
        @test bitop(conn, "AND", testkey3, testkey, testkey2) == 1

        for i=0:3
            setbit(conn, testkey, i, 1)
            setbit(conn, testkey2, i, 0)
        end
        bitop(conn, "AND", testkey3, testkey, testkey2)
        @test [getbit(conn, testkey3, i) for i in 0:3] == zeros(4)

        @test bitop(conn, "OR", testkey3, testkey, testkey2) == 1
        @test [getbit(conn, testkey3, i) for i in 0:3] == ones(4)

        setbit(conn, testkey, 0, 0)
        setbit(conn, testkey, 1, 0)
        setbit(conn, testkey2, 1, 1)
        setbit(conn, testkey2, 3, 1)
        @test bitop(conn, "XOR", testkey3, testkey, testkey2) == 1
        @test [getbit(conn, testkey3, i) for i in 0:3] == [0; 1; 1; 0]

        @test bitop(conn, "NOT", testkey3, testkey3) == 1
        @test [getbit(conn, testkey3, i) for i in 0:3] == [1; 0; 0; 1]
        del(conn, testkey, testkey2, testkey3)
    end

    @testset "Dump" begin
        # TODO: DUMP AND RESTORE HAVE ISSUES
        #=
        set(conn, testkey, "10")
        # this line passes test when a client is available:
        @test [UInt8(x) for x in Redis.dump(r, testkey)] == readbytes(`redis-cli dump t`)[1:end-1]
        =#

        #= this causes 'ERR DUMP payload version or checksum are wrong', a TODO:  need to
        translate the return value and send it back correctly
        set(conn, testkey, 1)
        redisdump = Redis.dump(conn, testkey)
        del(conn, testkey)
        restore(conn, testkey, 0, redisdump)
        =#
    end

    @testset "Migrate" begin
        # TODO: test of `migrate` requires 2 server instances in Travis
        set(conn, testkey, s1)
        @test move(conn, testkey, 1)
        @test exists(conn, testkey) == false
        @test Redis.select(conn, 1) == "OK"
        @test get(conn, testkey) == s1
        del(conn, testkey)
        Redis.select(conn, 0)
    end

    @testset "Expiry" begin
        set(conn, testkey, s1)
        expire(conn, testkey, 1)
        sleep(1)
        @test exists(conn, testkey) == false

        set(conn, testkey, s1)
        expireat(conn, testkey,  round(Int, Dates.datetime2unix(time(conn)+Dates.Second(1))))
        sleep(2) # only passes test with 2 second delay
        @test exists(conn, testkey) == false

        set(conn, testkey, s1)
        @test pexpire(conn, testkey, 1)
        sleep(1) # ensure key has expired
        @test ttl(conn, testkey) == REDIS_EXPIRED_KEY

        set(conn, testkey, s1)
        @test pexpire(conn, testkey, 2000)
        @test pttl(conn, testkey) > 100
        @test persist(conn, testkey)
        @test ttl(conn, testkey) == REDIS_PERSISTENT_KEY
        del(conn, testkey, testkey2, testkey3)
    end

    @testset "Lists" begin
        @test lpush(conn, testkey, s1, s2, "a", "a", s3, s4) == 6
        @test lpop(conn, testkey) == s4
        @test rpop(conn, testkey) == s1
        @test lpop(conn, "non_existent_list") === nothing
        @test rpop(conn, "non_existent_list") === nothing
        @test llen(conn, testkey) == 4
        @test lindex(conn, "non_existent_list", 1) === nothing
        @test lindex(conn, testkey, 0) == s3
        @test lindex(conn, testkey, 10) === nothing
        @test lrem(conn, testkey, 0, "a") == 2
        @test lset(conn, testkey, 0, s5) == "OK"
        @test lindex(conn, testkey, 0) == s5
        @test linsert(conn, testkey, "BEFORE", s2, s3) == 3
        @test linsert(conn, testkey, "AFTER", s3, s6) == 4
        @test lpushx(conn, testkey2, "nothing")  == false
        @test rpushx(conn, testkey2, "nothing")  == false
        @test ltrim(conn, testkey, 0, 1) == "OK"
        @test lrange(conn, testkey, 0, -1) == [s5; s3]
        @test brpop(conn, testkey, 0) == [testkey, s3]
        lpush(conn, testkey, s3)
        @test blpop(conn, testkey, 0) == [testkey, s3]
        lpush(conn, testkey, s4)
        lpush(conn, testkey, s3)
        listvals = [s3; s4; s5]
        for i in 1:3
            @test rpoplpush(conn, testkey, testkey2) == listvals[4-i]  # rpop
        end
        @test rpoplpush(conn, testkey, testkey2) === nothing
        @test llen(conn, testkey) == 0
        @test llen(conn, testkey2) == 3
        @test lrange(conn, testkey2, 0, -1) == listvals
        for i in 1:3
            @test brpoplpush(conn, testkey2, testkey, 0) == listvals[4-i]  # rpop
        end
        @test lrange(conn, testkey, 0, -1) == listvals

        # the following command can only be applied to lists containing numeric values
        sortablelist = [pi, 1, 2]
        lpush(conn, testkey3, sortablelist)
        @test Redis.sort(conn, testkey3) == ["1.0", "2.0", "3.141592653589793"]
        del(conn, testkey, testkey2, testkey3)
    end

    @testset "Hashes" begin
        @test hmset(conn, testhash, Dict(1 => 2, "3" => 4, "5" => "6"))
        @test hscan(conn,  testhash, 0) == (0, Dict("1" => "2", "3" => "4", "5" => "6"))
        @test hexists(conn, testhash, 1) == true
        @test hexists(conn, testhash, "1") == true
        @test hget(conn, testhash, 1) == "2"
        @test hgetall(conn, testhash) == Dict("1" => "2", "3" => "4", "5" => "6")

        @test hget(conn, testhash, "non_existent_field") === nothing
        @test hmget(conn, testhash, 1, 3) == ["2", "4"]
        a = hmget(conn, testhash, "non_existent_field1", "non_existent_field2")
        @test a[1] === nothing
        @test a[2] === nothing

        @test Set(hvals(conn, testhash)) == Set(["2", "4", "6"]) # use Set for comp as hash ordering is random
        @test Set(hkeys(conn, testhash)) == Set(["1", "3", "5"])
        @test hset(conn, testhash, "3", 10) == false # if the field already hset returns false
        @test hget(conn, testhash, "3") == "10" # but still sets it to the new value
        @test hset(conn, testhash, "10", "10") == true # new field hset returns true
        @test hget(conn, testhash, "10") == "10" # correctly set new field
        @test hsetnx(conn, testhash, "1", "10") == false # field exists
        @test hsetnx(conn, testhash, "11", "10") == true # field doesn't exist
        @test hlen(conn, testhash) == 5  # testhash now has 5 fields
        @test hincrby(conn, testhash, "1", 1) == 3
        @test parse(Float64, hincrbyfloat(conn, testhash, "1", 1.5)) == 4.5

        del(conn, testhash)

        N = 1500
        @test hmset(conn, testhash, Dict(i=>i for i=1:N))
        (cursor, d) = hscan(conn, testhash, 0)
        while cursor != 0
            (cursor, d_new) = hscan(conn, testhash, cursor)
            merge!(d, d_new)
        end
        @test d == Dict(string(i)=>string(i) for i=1:N)
        del(conn, testhash)
    end

    @testset "Sets" begin
        @test sadd(conn, testkey, s1) == true
        @test sadd(conn, testkey, s1) == false  # already exists
        @test sadd(conn, testkey, s2) == true
        @test smembers(conn, testkey) == Set([s1, s2])
        @test scard(conn, testkey) == 2
        sadd(conn, testkey, s3)
        @test smove(conn, testkey, testkey2, s3) == true
        @test sismember(conn, testkey2, s3) == true
        sadd(conn, testkey2, s2)
        @test sunion(conn, testkey, testkey2) == Set([s1, s2, s3])
        @test sunionstore(conn, testkey3, testkey, testkey2) == 3
        @test srem(conn, testkey3, s1, s2, s3) == 3
        @test smembers(conn, testkey3) == Set([])
        @test sinterstore(conn, testkey3, testkey, testkey2) == 1
        # only the following method returns 'nil' if the Set does not exist
        @test srandmember(conn, testkey3) in Set([s1, s2, s3])
        @test srandmember(conn, "empty_set") === nothing
        # this method returns an emtpty Set if the the Set is empty
        @test issubset(srandmember(conn, testkey2, 2), Set([s1, s2, s3]))
        @test srandmember(conn, "non_existent_set", 10) == Set{AbstractString}()
        @test sdiff(conn, testkey, testkey2) == Set([s1])
        @test spop(conn, testkey) in Set([s1, s2, s3])
        @test spop(conn, "empty_set") === nothing
        del(conn, testkey, testkey2, testkey3)
    end

    @testset "Sorted Sets" begin
        @test zadd(conn, testkey, 0, s1) == true
        @test zadd(conn, testkey, 1., s1) == false
        @test zadd(conn, testkey, 1., s2) == true
        @test zrange(conn, testkey, 0, -1) == OrderedSet([s1, s2])
        @test zcard(conn, testkey) == 2
        zadd(conn, testkey, 1.5, s3)
        @test zcount(conn, testkey, 0, 1) == 2   # range as int
        @test zcount(conn, testkey, "-inf", "+inf") == 3 # range as string
        @test zincrby(conn, testkey, 1, s1) == "2"
        @test parse(Float64, zincrby(conn, testkey, 1.2, s1)) == 3.2
        @test zrem(conn, testkey, s1, s2) == 2
        del(conn, testkey)

        @test zadd(conn, testkey, zip(zeros(3), [s1, s2, s3])...) == 3
        del(conn, testkey)

        vals = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j"]

        # tests where all scores == 0
        zadd(conn, testkey, zip(zeros(length(vals)), vals)...)
        @test zlexcount(conn, testkey, "-", "+") == length(vals)
        @test zlexcount(conn, testkey, "[b", "[f") == 5
        @test zrangebylex(conn, testkey, "-", "[c") == OrderedSet(["a", "b", "c"])
        @test zrangebylex(conn, testkey, "[aa", "(g") == OrderedSet(["b", "c", "d", "e", "f"])
        @test zrangebylex(conn, testkey, "[a", "(g") == OrderedSet(["a", "b", "c", "d", "e", "f"])
        @test zremrangebylex(conn, testkey, "[a", "[h") == 8
        @test zrange(conn, testkey, 0, -1) == OrderedSet(["i", "j"])
        del(conn, testkey)

        # tests where scores are sequence 1:10
        zadd(conn, testkey, zip(1:length(vals), vals)...)
        @test zrangebyscore(conn, testkey, "(1", "2") == OrderedSet(["b"])
        @test zrangebyscore(conn, testkey, "1", "2") == OrderedSet(["a", "b"])
        @test zrangebyscore(conn, testkey, "(1", "(2") == OrderedSet([])
        @test zrank(conn, testkey, "d") == 3 # redis arrays 0-base

        # 'NIL'
        @test zrank(conn, testkey, "z") === nothing
        del(conn, testkey)

        zadd(conn, testkey, zip(1:length(vals), vals)...)
        @test zremrangebyrank(conn, testkey, 0, 1) == 2
        @test zrange(conn, testkey, 0, -1, "WITHSCORES") == OrderedSet(["c", "3", "d", "4", "e", "5", "f", "6", "g", "7", "h", "8", "i", "9", "j", "10"])
        @test zremrangebyscore(conn, testkey, "-inf", "(5") == 2
        @test zrange(conn, testkey, 0, -1, "WITHSCORES") == OrderedSet(["e", "5", "f", "6", "g", "7", "h", "8", "i", "9", "j", "10"])
        @test zrevrange(conn, testkey, 0, -1) == OrderedSet(["j", "i", "h", "g", "f", "e"])
        @test zrevrangebyscore(conn, testkey, "+inf", "-inf") == OrderedSet(["j", "i", "h", "g", "f", "e"])
        @test zrevrangebyscore(conn, testkey, "+inf", "-inf", "WITHSCORES", "LIMIT", 2, 3) == OrderedSet(["h", "8", "g", "7", "f", "6"])
        @test zrevrangebyscore(conn, testkey, 7, 5) == OrderedSet(["g", "f", "e"])
        @test zrevrangebyscore(conn, testkey, "(6", "(5") == OrderedSet{AbstractString}()
        @test zrevrank(conn, testkey, "e") == 5
        @test zrevrank(conn, "ordered_set", "non_existent_member") === nothing
        @test zscore(conn, testkey, "e") == "5"
        @test zscore(conn, "ordered_set", "non_existent_member") === nothing
        del(conn, testkey)

        vals2 = ["a", "b", "c", "d"]
        zadd(conn, testkey, zip(1:length(vals), vals)...)
        zadd(conn, testkey2, zip(1:length(vals2), vals2)...)
        @test zunionstore(conn, testkey3, 2, [testkey, testkey2]) == 10
        @test zrange(conn, testkey3, 0, -1) == OrderedSet(vals)
        del(conn, testkey3)

        zunionstore(conn, testkey3, 2, [testkey, testkey2], [2; 3])
        @test zrange(conn, testkey3, 0, -1) == OrderedSet(["a", "b", "e", "f", "g", "c", "h", "i", "d", "j"])
        zunionstore(conn, testkey3, 2, [testkey, testkey2], [2; 3], aggregate=Aggregate.Max)
        @test zrange(conn, testkey3, 0, -1) == OrderedSet(["a", "b", "c", "e", "d", "f", "g", "h", "i", "j"])
        zunionstore(conn, testkey3, 2, [testkey, testkey2], [2; 3], aggregate=Aggregate.Min)
        @test zrange(conn, testkey3, 0, -1) == OrderedSet(["a", "b", "c", "d", "e", "f", "g", "h", "i", "j"])
        del(conn, testkey3)

        vals2 = ["a", "b", "c", "d"]
        @test zinterstore(conn, testkey3, 2, [testkey, testkey2]) == 4
        del(conn, testkey, testkey2, testkey3)

        # test using bzpopmin
        vals2 = ["a", "b", "c", "d"]
        zadd(conn, testkey, zip([4, 2, 1, 3], vals2)...)
        @test bzpopmin(conn, testkey, 0) == [testkey, "c", "1"]
        @test bzpopmin(conn, testkey, 0) == [testkey, "b", "2"]
        @test bzpopmin(conn, testkey, 0) == [testkey, "d", "3"]
        @test bzpopmin(conn, testkey, 0) == [testkey, "a", "4"]
        @test bzpopmin(conn, testkey, 0.1) == nothing
        del(conn, testkey)
    end

    @testset "Scan" begin

    end

    @testset "Scripting" begin
        script = "return {KEYS[1], KEYS[2], ARGV[1], ARGV[2]}"
        keys = ["key1", "key2"]
        args = ["first", "second"]
        resp = evalscript(conn, script, 2, keys, args)
        @test resp == vcat(keys, args)
        del(conn, "key1")

        script = "return redis.call('set', KEYS[1], 'bar')"
        ky = "foo"
        resp = evalscript(conn, script, 1, [ky], [])
        @test resp == "OK"
        del(conn, ky)

        script = "return {10,20}"
        resp = evalscript(conn, script, 0, [], [])
        @test resp == [10, 20]

        script = "return"
        resp = evalscript(conn, script, 0, [], [])
        @test resp === nothing

    #@test evalscript(conn, "return {'1','2',{'3','Hello World!'}}", 0, []) == ["1"; "2"; ["3","Hello World!"]]

    # NOTE the truncated float, and truncated array in the response
    # as per http://redis.io/commands/eval
    #       Lua has a single numerical type, Lua numbers. There is
    #       no distinction between integers and floats. So we always
    #       convert Lua numbers into integer replies, removing the
    #       decimal part of the number if any. If you want to return
    #       a float from Lua you should return it as a string, exactly
    #       like Redis itself does (see for instance the ZSCORE command).
    #
    #       There is no simple way to have nils inside Lua arrays,
    #       this is a result of Lua table semantics, so when Redis
    #       converts a Lua array into Redis protocol the conversion
    #       is stopped if a nil is encountered.
    #@test evalscript(conn, "return {1, 2, 3.3333, 'foo', nil, 'bar'}",  0, []) == [1, 2, 3, "foo"]
    end

    @testset "Transactions" begin
        trans = open_transaction(conn)
        @test set(trans, testkey, "foobar") == "QUEUED"
        @test get(trans, testkey) == "QUEUED"
        @test exec(trans) == ["OK", "foobar"]
        @test del(trans, testkey) == "QUEUED"
        @test exec(trans) == [true]
        @test evalscript(trans, "return", 0, [], []) == "QUEUED"
        @test exec(trans) == [nothing]
        disconnect(trans)
    end

    @testset "Pipelines" begin
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
        result = read_pipeline(pipe)
        @test result ==  [1, 1]

        evalscript(pipe, "return", 0, [], [])
        result = read_pipeline(pipe)
        @test result == []
        disconnect(pipe)
    end

    @testset "Pub/Sub" begin
        function handleException(ex)
            io = IOBuffer()
            showerror(io, ex, catch_backtrace())
            err = String(take!(io))
            @warn "Error while processing subscription: $err"
            return nothing
        end

        string_matched_results = Any[]
        pattern_matched_results = Any[]

        function string_matched(y::AbstractString)
            push!(string_matched_results, y)
        end

        function pattern_matched(y::AbstractString)
            push!(pattern_matched_results, y)
        end

        subs = open_subscription(conn, handleException) #handleException is called when an exception occurs

        subscribe_data(subs, "1channel", string_matched)
        psubscribe_data(subs, "1cha??el", pattern_matched)

        subscribe(subs, "2channel", y->string_matched(y.message))
        psubscribe(subs, "2chan*", y->pattern_matched(y.message))

        subscribe_data(subs, Dict("3channel" => string_matched))
        psubscribe_data(subs, Dict("3cha??el" => pattern_matched))

        subscribe(subs, Dict("4channel" => y->string_matched(y.message)))
        psubscribe(subs, Dict("4chan*" => y->pattern_matched(y.message)))

        published_messages = ["hello, world1!", "hello, world 2!", "hello, world 3!", "hello, world 4!"]

        sleep(10)   # to ensure all subscriptions are registered
        
        for idx in 1:4
            @test publish(conn, string(idx)*"channel", published_messages[idx]) > 0 #Number of connected clients returned
        end

        timedwait(5.0; pollint=1.0) do # wait for the messages to be received
            length(string_matched_results) == 4 && length(pattern_matched_results) == 4        
        end

        @test string_matched_results == published_messages
        @test pattern_matched_results == published_messages

        # following command prints ("Invalid response received: ")
        disconnect(subs)
        @info "This error is expected - to be addressed once the library is stable."
    end

    disconnect(conn)
end
