module TestReduce

using FLoops
using Test
using Transducers: SplitBy

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


function floop_with_init_binops(xs, ex = nothing)
    @floop ex for x in xs
        @reduce(s = 0 + x, c = 0 + 1)
    end
    return f() = (s, c)
end

function two_floops(xs, ex = nothing)
    @floop ex for x in xs
        @reduce(s = 0 + x, c = 0 + 1)
    end
    @floop ex for x in xs
        @reduce(v = 0 + (x - (s / c))^2)
    end
    return v / c
end

@testset "empty" begin
    @test !FLoops.has_boxed_variables(floop_with_init_binops(1:10))
    @test two_floops(1:8) == 5.25
end

function sum_arrays(arrays, ex = nothing)
    @floop ex for x in arrays
        # @reduce(s = zero(y) .+ y)  # TODO
        @reduce() do (s = zero(x); x)
            s .+= x
        end
    end
    return s
end

@testset "@reduce init scope" begin
    @test sum_arrays([[1], [2], [3]]) == [sum(1:3)]
    @test sum_arrays([[1], [2], [3]], SequentialEx()) == [sum(1:3)]
    @testset "let" begin
        local y = 0
        @floop for x in 1:10
            let y = 123
            end
            @reduce(s = y + x)
        end
        @test s == sum(1:10)
    end
end

function maximum_partition_length(f, xs, ex = nothing)
    @floop ex for chunk in SplitBy(f)(xs)
        @reduce m = max(typemin(Int), length(chunk))
    end
    return m
end

@testset "SplitBy" begin
    @test maximum_partition_length(isodd, 1:10) == 1
    @test maximum_partition_length(isodd, 1:10, SequentialEx()) == 1
    @test maximum_partition_length(==(7), 1:10) == 6
    @test maximum_partition_length(==(7), 1:10, SequentialEx()) == 6
    xs = rand(0:9, 1000)
    @test maximum_partition_length(iszero, xs) ==
          maximum_partition_length(iszero, xs, SequentialEx())
end

function sum_halved_arrays(arrays, ex = nothing)
    @floop ex for x in arrays
        @init y = zero(x)
        y .= x .÷ 2
        @reduce(s = 0 + sum(y))
    end
    return s
end

function two_inits(arrays, ex = nothing)
    @floop ex for x in arrays
        @init begin
            y = zero(x)
            z = similar(y)
        end
        y .= x .÷ 2
        z .= 2 .* y
        r = sum(a * b for (a, b) in zip(y, z))
        @reduce(s = 0 + r)
    end
    return s
end

function two_inits2(arrays, ex = nothing)
    @floop ex for x in arrays
        @init y = zero(x)
        @init z = similar(y)
        y .= x .÷ 2
        z .= 2 .* y
        r = sum(a * b for (a, b) in zip(y, z))
        @reduce(s = 0 + r)
    end
    return s
end

@testset "@init" begin
    arrays = [[1, 2], [3, 4], [5, 6], [7, 8]]
    desired = sum(sum(x .÷ 2) for x in arrays)
    @test sum_halved_arrays(arrays) == desired
    @test sum_halved_arrays(arrays, SequentialEx()) == desired

    desired = sum((c ÷ 2) * (2 * (c ÷ 2)) for x in arrays for c in x)
    @test two_inits(arrays) == desired
    @test two_inits(arrays, SequentialEx()) == desired
    @test two_inits2(arrays) == desired
    @test two_inits2(arrays, SequentialEx()) == desired
end

@testset "just @init" begin
    n = 10
    dest = zeros(Int, n)
    @floop for (i, x) in pairs(1:n)
        @init y = zeros(Int, 3)
        y .= (x, 2x, 3x)
        dest[i] = y[1]
    end
    @test dest == 1:n
end

function probe_init(xs, ex = nothing)
    ninit = Threads.Atomic{Int}(0)
    @floop ex for x in xs
        @init y = begin
            Threads.atomic_add!(ninit, 1)
            nothing
        end
    end
    return ninit[]
end

@testset "@init called once" begin
    @testset "default" begin
        @test probe_init(1:(Threads.nthreads() * 100)) == Threads.nthreads()
    end
    @testset "SequentialEx" begin
        @test probe_init(1:(Threads.nthreads() * 100), SequentialEx()) == 1
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

@testset "unprocessed @init" begin
    err = try
        @init x = 0
        nothing
    catch err
        err
    end
    @test err isa FLoops.InitSpec
    @test occursin("used outside `@floop`", sprint(showerror, err))
end

@testset "invalid @init" begin
    @testset "toplevel" begin
        err = try
            @eval @init(a)
            nothing
        catch err
            err
        end
        @test err isa Exception
        @test occursin("requires an assignment", sprint(showerror, err))
    end
    @testset "non assignment (+=)" begin
        err = try
            @eval @init a += 1
            nothing
        catch err
            err
        end
        @test err isa Exception
        @test occursin("requires an assignment", sprint(showerror, err))
    end
    @testset "non assignment (constant)" begin
        err = try
            @eval @init begin
                a = 1
                1
            end
            nothing
        catch err
            err
        end
        @test err isa Exception
        @test occursin("requires an assignment", sprint(showerror, err))
    end
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
