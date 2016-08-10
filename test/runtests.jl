using Redis
import DataStructures: OrderedSet

if VERSION >= v"0.5.0-dev+7720"
    using Base.Test
else
    using BaseTestNext
    const Test = BaseTestNext
end

include(joinpath(dirname(@__FILE__),"client_tests.jl"))
include(joinpath(dirname(@__FILE__),"redis_tests.jl"))
