using Test, Redis, Harbor

@testset "Redis" begin
    @testset "readresponse" begin
        simple_string = UInt8[0x2B, 0x4F, 0x4B, 0x0D, 0x0A]
        x = Redis.readresponse(IOBuffer(simple_string))
        @test x == "OK"
        error_message = UInt8[0x2D, 0x45, 0x72, 0x72, 0x6F, 0x72, 0x20, 0x6D, 0x65, 0x73, 0x73, 0x61, 0x67, 0x65, 0x0D, 0x0A]
        @test_throws Redis.RedisError Redis.readresponse(IOBuffer(error_message))
        integer_response = UInt8[0x3A, 0x31, 0x30, 0x30, 0x30, 0x0D, 0x0A]
        x = Redis.readresponse(Int, IOBuffer(integer_response))
        @test x == 1000
        bulk_string = UInt8[0x24, 0x36, 0x0D, 0x0A, 0x66, 0x6F, 0x6F, 0x62, 0x61, 0x72, 0x0D, 0x0A]
        x = Redis.readresponse(IOBuffer(bulk_string))
        @test x == "foobar"
        null_bulk_string = UInt8[0x24, 0x2D, 0x31, 0x0D, 0x0A]
        x = Redis.readresponse(IOBuffer(null_bulk_string))
        @test x === nothing
        array_response = UInt8[
            0x2A, 0x32, 0x0D, 0x0A,  # *2\r\n
            0x24, 0x33, 0x0D, 0x0A,  # $3\r\n
            0x66, 0x6F, 0x6F, 0x0D, 0x0A,  # foo\r\n
            0x24, 0x33, 0x0D, 0x0A,  # $3\r\n
            0x62, 0x61, 0x72, 0x0D, 0x0A   # bar\r\n
        ]
        x = Redis.readresponse(Vector{String}, IOBuffer(array_response))
        @test x == ["foo", "bar"]
        mixed_array = UInt8[
            0x2A, 0x33, 0x0D, 0x0A,  # *3\r\n
            0x3A, 0x31, 0x0D, 0x0A,  # :1\r\n
            0x3A, 0x32, 0x0D, 0x0A,  # :2\r\n
            0x3A, 0x33, 0x0D, 0x0A   # :3\r\n
        ]
        x = Redis.readresponse(Vector{Int}, IOBuffer(mixed_array))
        @test x == [1, 2, 3]
        nested_array = UInt8[
            0x2A, 0x32, 0x0D, 0x0A,  # *2\r\n
            0x2A, 0x33, 0x0D, 0x0A,  # *3\r\n
            0x3A, 0x31, 0x0D, 0x0A,  # :1\r\n
            0x3A, 0x32, 0x0D, 0x0A,  # :2\r\n
            0x3A, 0x33, 0x0D, 0x0A,  # :3\r\n
            0x2A, 0x32, 0x0D, 0x0A,  # *2\r\n
            0x2B, 0x46, 0x6F, 0x6F, 0x0D, 0x0A,  # +Foo\r\n
            0x2D, 0x42, 0x61, 0x72, 0x0D, 0x0A   # -Bar\r\n
        ]
        @test_throws Redis.RedisError Redis.readresponse(Vector{Vector{String}}, IOBuffer(nested_array))
        nested_array2 = UInt8[
            0x2A, 0x32, 0x0D, 0x0A,  # *2\r\n
            0x2A, 0x33, 0x0D, 0x0A,  # *3\r\n
            0x3A, 0x31, 0x0D, 0x0A,  # :1\r\n
            0x3A, 0x32, 0x0D, 0x0A,  # :2\r\n
            0x3A, 0x33, 0x0D, 0x0A,  # :3\r\n
            0x2A, 0x32, 0x0D, 0x0A,  # *2\r\n
            0x2B, 0x46, 0x6F, 0x6F, 0x0D, 0x0A,  # +Foo\r\n
            0x2B, 0x42, 0x61, 0x72, 0x0D, 0x0A   # +Bar\r\n
        ]
        x = Redis.readresponse(Vector{Any}, IOBuffer(nested_array2))
        @test x == [[1, 2, 3], ["Foo", "Bar"]]
        null_array = UInt8[0x2A, 0x2D, 0x31, 0x0D, 0x0A]
        x = Redis.readresponse(Vector{String}, IOBuffer(null_array))
        @test x === nothing
        empty_array = UInt8[0x2A, 0x30, 0x0D, 0x0A]
        x = Redis.readresponse(Vector{String}, IOBuffer(empty_array))
        @test x == []
    end

    @testset "Basic connections" begin
        Harbor.with_container("redis"; wait_strategy=(pattern="Ready to accept connections tcp",), ports=Dict(6379 => 6379), command=["redis-server"]) do _
            redis = Redis.connect("127.0.0.1", 6379)
            Redis.set(redis, "key2", "value2")
            @test Redis.get(redis, "key2") == "value2"
            # cleanup
            Redis.del(redis, "key2")
            # batch execution
            cmds = [
                Redis.Commands.set("batchkey1", "v1"),
                Redis.Commands.set("batchkey2", "v2"),
                Redis.Commands.get("batchkey1"),
                Redis.Commands.get("batchkey2")
            ]
            results = Redis.execute_batch(redis, cmds)
            @test results[1] == "OK"
            @test results[2] == "OK"
            @test results[3] == "v1"
            @test results[4] == "v2"
            # Cleanup
            Redis.del(redis, "batchkey1")
            Redis.del(redis, "batchkey2")
        end
        Harbor.with_container("redis"; wait_strategy=(pattern="Ready to accept connections tcp",), ports=Dict(6379 => 6379), command=["redis-server", "--requirepass", "yourpassword"]) do _
            redis = Redis.connect("127.0.0.1", 6379; password="yourpassword")
            Redis.set(redis, "key1", "value1")
            @test Redis.get(redis, "key1") == "value1"
            # cleanup
            Redis.del(redis, "key1")
        end
    end
end


# requires running local redis
# using AwsIO, LibAwsCommon, Redis
# redis = Redis.connect("localhost", 6380; password="yourpassword")

# function fuzzRedis(redis)
#     AwsIO.Sockets.trace_memory!(LibAwsCommon.AWS_MEMTRACE_STACKS)
#     vals = Dict{String, String}("hey" => "ho")
#     Redis.set(redis, "hey", "ho")
#     for i in 1:1000
#         command = rand(["SET", "GET"])
#         if command == "GET"
#             key = rand(keys(vals))
#             val = Redis.get(redis, key)
#             @info "GET $key => $val" i=i
#         else
#             key = String(rand('a':'z', 21))
#             val = String(rand('a':'z', rand(1:1000)))
#             vals[key] = val
#             Redis.set(redis, key, val)
#             @info "SET $key => $val" i=i
#         end
#     end
#     AwsIO.Sockets.set_log_level!(7)
#     AwsIO.Sockets.trace_memory_dump()
#     AwsIO.Sockets.set_log_level!(0)
#     # AwsIO.Sockets.set_log_level!(0)
#     for (k, _) in vals
#         Redis.del(redis, k)
#     end
#     return
# end
# fuzzRedis(redis)