using Redis
import DataStructures: OrderedSet
using Random
using Dates
using Test
using Base

include(joinpath(dirname(@__FILE__),"client_tests.jl"))
include(joinpath(dirname(@__FILE__),"redis_tests.jl"))
