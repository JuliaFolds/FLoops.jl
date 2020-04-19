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

@testset "@inbounds" begin
    xs = 1:10
    @floop begin
        s = 0
        @inbounds for x in xs
            s += x
        end
    end
    @test s == sum(xs)
end

@testset "function" begin
    xs = 1:10
    @floop begin
        s = 0
        @inbounds for x in xs
            f() = return s + x
            s = f()
        end
    end
    @test s == sum(xs)
end

@testset "let + break" begin
    function demo(xs)
        @floop begin
            s = 0
            p = 1
            for x in xs
                s += x
                p *= x
                let p = x
                    if p == 5
                        s = 0
                        break
                    end
                end
            end
        end
        return (s, p)
    end
    @test demo(1:10) == (0, prod(1:5))
    @test demo(1:4) == (sum(1:4), prod(1:4))
end

@testset "let + continue" begin
    function demo(xs)
        @floop begin
            s = 0
            p = 1
            for x in xs
                let p = x
                    if p == 5
                        s = 0
                        continue
                    end
                end
                s += x
                p *= x
            end
        end
        return (s, p)
    end
    @test demo(1:10) == (sum(6:10), prod(1:10) ÷ 5)
    @test demo(1:4) == (sum(1:4), prod(1:4))
end

@testset "continue" begin
    xs = 1:3
    ys = []
    @floop for x in xs
        x == 1 && continue
        push!(ys, x)
    end
    @test ys == [2, 3]
end

@testset "break" begin
    xs = 1:3
    ys = []
    @floop for x in xs
        push!(ys, x)
        x == 2 && break
    end
    @test ys == [1, 2]
end

@testset "return" begin
    function demo()
        ys = []
        @floop for x in 1:3
            push!(ys, x)
            if x == 2
                return ys
            end
        end
    end
    @test demo() == [1, 2]
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
