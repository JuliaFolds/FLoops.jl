module TestReduce

using FLoops
using Test

@testset "sum" begin
    @floop for (x, y) in zip(1:3, 1:2:6)
        a = x + y
        b = x - y
        @reduce(s += a, t += b)
    end
    @test (s, t) === (15, -3)
end

@testset "sum with init" begin
    @floop for (x, y) in zip(1:3, 1:2:6)
        a = x + y
        b = x - y
        @reduce(s = 0im + a, t = 0im + b)
    end
    @test (s, t) === (15 + 0im, -3 + 0im)
end

@testset "sum, nested loop" begin
    @floop for x in 1:3, y in 1:2:6
        a = x + y
        b = x - y
        @reduce(s += a, t += b)
    end
    @test (s, t) === (45, -9)
end

@testset "findmax" begin
    @floop for (i, v) in pairs([0, 1, 3, 2])
        y = 2v
        @reduce() do (ymax = -Inf; y), (imax = 0; i)
            if isless(ymax, y)
                ymax = y
                imax = i
            end
        end
    end
    @test (ymax, imax) == (6, 3)
end

@testset "findminmax" begin
    @floop for (i, v) in pairs([0, 1, 3, 2])
        y = 2v
        @reduce() do (ymax = -Inf; y), (imax = 0; i)
            if isless(ymax, y)
                ymax = y
                imax = i
            end
        end
        @reduce() do (ymin = Inf; y), (imin = 0; i)
            if isless(y, ymin)
                ymin = y
                imin = i
            end
        end
    end
    @test (ymax, imax) == (6, 3)
    @test (ymin, imin) == (0, 1)
end

@testset "break" begin
    @floop for x in 1:10
        @reduce(s += x)
        x == 3 && break
    end
    @test s == 6
end

@testset "findmax with filtering" begin
    @floop for (i, v) in pairs([0, 1, 4, 3, 1])
        if isodd(v)
            @reduce() do (vmax = -Inf; v), (imax = 0; i)
                if isless(vmax, v)
                    vmax = v
                    imax = i
                end
            end
        end
    end
    @test (vmax, imax) == (3, 4)
end

@testset "non-unique arguments" begin
    @testset "`@reduce(a += x, b *= x)`" begin
        xs = 1:10
        @floop for x in xs
            @reduce(a += x, b *= x)
        end
        @test (sum(xs), prod(xs)) == (a, b)
    end

    @testset "`@reduce(a = 0 + x, b = 1 * x)`" begin
        xs = 1:10
        @floop for x in xs
            @reduce(a = 0 + x, b = 1 * x)
        end
        @test (sum(xs), prod(xs)) == (a, b)
    end

    @testset "`@reduce a = 0 + x; @reduce b = 1 * x`" begin
        xs = 1:10
        @floop for x in xs
            @reduce a = 0 + x
            @reduce b = 1 * x
        end
        @test (sum(xs), prod(xs)) == (a, b)
    end
end

@testset "unprocessed @reduce" begin
    err = try
        @reduce(s += y, p *= y)
        nothing
    catch err
        err
    end
    @test err isa FLoops.ReduceOpSpec
    @test occursin("used outside `@floop`", sprint(showerror, err))
end

@testset "duplicated accumulators" begin
    err = try
        @eval @macroexpand @floop for x in xs
           @reduce(y += x, y += x)
        end
        nothing
    catch err
        err
    end
    @test err isa Exception
    @test occursin("`y` used 2 times", sprint(showerror, err))
end

end  # module
