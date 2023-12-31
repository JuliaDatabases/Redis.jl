using Redis
import DataStructures: OrderedSet
using Random
using Dates
using Test
using Base
using MbedTLS

include("test_utils.jl")
include("client_tests.jl")
include("redis_tests.jl")

client_tests()

# TCP connection
redis_tests(RedisConnection())

# TLS connection
redis_tests(RedisConnection(; port=16379, sslconfig=client_tls_config(joinpath(@__DIR__, "certs", "ca.crt"))))