using Redis
import DataStructures: OrderedSet

if VERSION >= v"0.5.0-dev+7720"
    using Base.Test
else
    using BaseTestNext
    const Test = BaseTestNext
end

include(Pkg.dir("Redis","test","client_tests.jl"))
include(Pkg.dir("Redis","test","redis_tests.jl"))
