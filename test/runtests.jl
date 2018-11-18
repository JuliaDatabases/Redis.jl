using Redis
import DataStructures: OrderedSet
using Random
using Test


include(joinpath(dirname(@__FILE__),"client_tests.jl"))
include(joinpath(dirname(@__FILE__),"redis_tests.jl"))
