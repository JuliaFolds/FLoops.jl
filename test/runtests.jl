using FLoops
using Test

@testset "two states" begin
    xs = 1:10
    @floop begin
        s = 0
        p = 1
        for x in xs
            s += x
            p *= x
        end
    end
    @test s == sum(xs)
    @test p == prod(xs)
end

@testset "no states" begin
    xs = 1:10
    ys = similar(xs)
    @floop for (i, x) in enumerate(xs)
        ys[i] = 2x
    end
    @test ys == 2 .* xs
end

@testset "product" begin
    xs = 1:10
    ys = 2:3:15
    actual = []
    @floop for x in xs, y in ys
        push!(actual, (y, x))
    end
    desired = []
    for x in xs, y in ys
        push!(desired, (y, x))
    end
    @test actual == desired
end

@testset "triangular" begin
    xs = 1:10
    actual = []
    @floop for x in xs, y in x:2:10
        push!(actual, (y, x))
    end
    desired = []
    for x in xs, y in x:2:10
        push!(desired, (y, x))
    end
    @test actual == desired
end

@testset "internal goto" begin
    xs = 1:10
    @floop begin
        s = 0
        for x in xs
            @goto a
            s += x
            @label a
        end
    end
    @test s == 0
end

@testset "external goto" begin
    xs = 1:10
    @floop begin
        s = 0
        for x in xs
            s += x
            s > 5 && @goto a
        end
    end
    @label a
    @test s == 6
end
