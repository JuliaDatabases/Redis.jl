import Redis: flatten, flatten_command, convert_response

@testset "Flatten" begin
    @test flatten("simple") == "simple"
    @test flatten(1) == "1"
    @test flatten(2.5) == "2.5"
    @test flatten([1, "2", 3.5]) == ["1", "2", "3.5"]

    s = Set([1, 5, "10.9"])
    @test Set(flatten(s)) == Set(["1", "5", "10.9"])

    d = Dict{Any, Any}(1 => 2, 3 => 4)
    @test Set(flatten(d)) == Set(["1", "2", "3", "4"])
end

@testset "Commands" begin
    result = flatten_command(1, 2, ["4", "5", 6.7], 8)
    @test result == ["1", "2", "4", "5", "6.7", "8"]
end

@testset "Convert" begin
    @test convert_response(Dict{AbstractString, AbstractString}, ["1","2","3","4"]) == Dict("1" => "2", "3" => "4")
    @test convert_response(Dict{AbstractString, AbstractString}, []) == Dict()
    @test_approx_eq convert_response(Float64, "12.3") 12.3
    @test_approx_eq convert_response(Float64, 10) 10.0
    @test convert_response(Bool, "OK")
    @test !convert_response(Bool, "f")
    @test convert_response(Bool, 1)
    @test !convert_response(Bool, 0)
end
