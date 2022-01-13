module TestReduce

using FLoops
using MicroCollections
using Test
using Transducers: SplitBy

function test_sum()
    @floop for (x, y) in zip(1:3, 1:2:6)
        a = x + y
        b = x - y
        @reduce(s += a, t += b)
    end
    @test (s, t) === (15, -3)
end

function test_sum_with_init()
    @floop for (x, y) in zip(1:3, 1:2:6)
        a = x + y
        b = x - y
        @reduce(s = 0im + a, t = 0im + b)
    end
    @test (s, t) === (15 + 0im, -3 + 0im)
end

function test_sum_nested_loop()
    @floop for x in 1:3, y in 1:2:6
        a = x + y
        b = x - y
        @reduce(s += a, t += b)
    end
    @test (s, t) === (45, -9)
end

function test_findmax()
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

function test_findminmax()
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

function sum_arrays_broadcast(arrays, ex = nothing)
    @floop ex for x in arrays
        @reduce s .+= x
    end
    try
        return s
    catch err
        return err
    end
end

function test_simple_broadcast()
    @test sum_arrays_broadcast([[1], [2], [3]]) == [sum(1:3)]
    @test sum_arrays_broadcast([[1], [2], [3]], SequentialEx()) == [sum(1:3)]
    @test sum_arrays_broadcast([]) == UndefVarError(:s)
    @test sum_arrays_broadcast([], SequentialEx()) == UndefVarError(:s)
end

function fused_broadcast(xs)
    ys = nothing
    vs = 1:2:11
    @floop for x in xs
        @reduce ys .+= vs .== x
    end
    return ys
end

function test_fused_broadcast()
    function desired(n)
        m = cld(n, 2)
        return [ones(Int, m); zeros(Int, 6 - m)]
    end
    @test fused_broadcast(1:0) === nothing
    @testset for n in 1:11
        @test fused_broadcast(1:n) == desired(n)
    end
end

⊕(a, b) = a .+ b

function mixed_broadcasts(xs)
    @floop for x in xs
        @reduce(
            a .+= x,              # symbol
            b .+= isodd.(x),      # dot call
            c .+= .√(x),          # unary dot op
            d .+= x .- 1,         # binary dot op
            e .+= prod(x),        # normal call
            f .+= x ⊕ 1,          # normal binary op
            g .+= -x,             # normal unary op
        )
    end
    try
        return (a = a, b = b, c = c, d = d, e = e, f = f, g = g)
    catch err
        return err
    end
end

function test_mixed_broadcasts()
    @test mixed_broadcasts([[4], [9]]) ==
          (a = [13], b = [1], c = [5], d = [11], e = 13, f = [15], g = [-13])
    @test mixed_broadcasts([[4]]) ==
          (a = [4], b = [0], c = [2], d = [3], e = 4, f = [5], g = [-4])
    @test mixed_broadcasts(1:0) == UndefVarError(:a)
end

function sum_onehot(indices, ex = nothing)
    l, h = extrema(indices)
    n = h - l + 1
    @floop ex for i in indices
        @inbounds @reduce h .+= OneHotVector(i - l + 1 => 1, n)
    end
    return h
end

function test_onehot()
    @testset "$(repr(ex))" for ex in [SequentialEx(), nothing]
        @test sum_onehot(1:3, ex) == [1, 1, 1]
        @test sum_onehot([1, 2, 4, 1], ex) == [2, 1, 0, 1]
    end
end

function test_break()
    @floop for x in 1:10
        @reduce(s += x)
        x == 3 && break
    end
    @test s == 6
end

function test_findmax_with_filtering()
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

function test_nonunique_arguments()
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

function test_empty()
    @test !FLoops.has_boxed_variables(floop_with_init_binops(1:10))
    @test two_floops(1:8) == 5.25
end

function sum_arrays(arrays, ex = nothing)
    @floop ex for x in arrays
        @reduce() do (s = zero(x); x)
            s .+= x
        end
    end
    return s
end

function test_at_reduce_init_scope()
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

function sum_arrays2(arrays, ex = nothing)
    @floop ex for x in arrays
        @reduce(s = zero(x) + x)
    end
    try
        return s
    catch err
        return err
    end
end

function test_init_in_loop()
    @test sum_arrays2([[1], [2], [3]]) == [sum(1:3)]
    @test sum_arrays2([[1], [2], [3]], SequentialEx()) == [sum(1:3)]
    @test sum_arrays2([]) == UndefVarError(:s)
    @test sum_arrays2([], SequentialEx()) == UndefVarError(:s)
end

function maximum_partition_length(f, xs, ex = nothing)
    @floop ex for chunk in SplitBy(f)(xs)
        @reduce m = max(typemin(Int), length(chunk))
    end
    return m
end

function test_SplitBy()
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

function test_at_init()
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

function test_just_at_init()
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

function test_at_init_called_once()
    @testset "default" begin
        @test probe_init(1:(Threads.nthreads()*100)) == Threads.nthreads()
    end
    @testset "SequentialEx" begin
        @test probe_init(1:(Threads.nthreads()*100), SequentialEx()) == 1
    end
end

function init_is_private(xs, ex = nothing)
    @floop ex for x in xs
        @init p = []
        push!(p, x)
        y = pop!(p)
        @reduce s += y
    end
    return (sum = s, isdefined_p = @isdefined(p))
end

function test_init_is_private()
    @test init_is_private(1:10) == (sum = sum(1:10), isdefined_p = false)
    @test init_is_private(1:10, SequentialEx()) == (sum = sum(1:10), isdefined_p = false)
end

function test_unprocessed_at_reduce()
    err = try
        @reduce(s += y, p *= y)
        nothing
    catch err
        err
    end
    @test err isa FLoops.ReduceOpSpec
    @test occursin("used outside `@floop`", sprint(showerror, err))
end

function test_unprocessed_at_init()
    err = try
        @init x = 0
        nothing
    catch err
        err
    end
    @test err isa FLoops.InitSpec
    @test occursin("used outside `@floop`", sprint(showerror, err))
end

function test_invalid_at_init()
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

function test_duplicated_accumulators()
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
