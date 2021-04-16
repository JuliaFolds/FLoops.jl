using Test
using FLoops

tests = Main.include(joinpath(@__DIR__, "in_main.jl"))

@testset "smoketest" begin
    @test tests.smoketest(DistributedEx()) isa Any
end

@testset "sumwith" begin
    @test tests.sumwith(identity, 1:10, DistributedEx()) == sum(1:10)
end

@testset "useinit" begin
    if VERSION >= v"1.6"
        @test tests.useinit(1:10, DistributedEx()) == sum(1:10)
    end
end
