module TestExecutors

using FLoops
using Test

function f_copy(executor)
    xs = 1:10
    ys = zeros(10)
    @floop executor for i in eachindex(xs, ys)
        ys[i] = xs[i]
    end
    return ys
end

function f_sum(executor)
    @floop executor for x in 1:10
        @reduce(s += x)
    end
    return s
end

function f_filter_sum(executor)
    @floop executor for x in 1:10
        if isodd(x)
            @reduce(s += x)
        end
    end
    return s
end

function f_sum_nested_loop(executor)
    @floop executor for x in 1:10
        for y in 1:x
            @reduce(s += y)
        end
    end
    return s
end

function f_sum_update(executor)
    @floop executor for x in 1:10
        if isodd(x)
            @reduce(s += 2x)
        end
    end
    return s
end

function f_sum_op_init(executor)
    @floop executor for x in 1:10
        if isodd(x)
            @reduce(s = 0 + 2x)
        end
    end
    return s
end

function f_count_update(executor)
    @floop executor for x in 1:10
        if isodd(x)
            @reduce(s += 1)
        end
    end
    return s
end

function f_count_op_init(executor)
    @floop executor for x in 1:10
        if isodd(x)
            @reduce(s = 0 + 1)
        end
    end
    return s
end

function f_sum_continue(executor)
    @floop executor for x in 1:10
        x > 4 && continue
        @reduce(s += x)
    end
    return s
end

function f_sum_break(executor)
    @floop executor for x in 1:10
        @reduce(s += x)
        x == 3 && break
    end
    return s
end

function f_find_return(executor)
    @floop executor for x in 1:10
        @reduce(s += x)
        x == 3 && return (:found, x)
    end
    return s
end

function f_find_goto(executor)
    @floop executor for x in 1:10
        @reduce() do (s; x)
            s = x
        end
        x == 3 && @goto FOUND
    end
    return s
    @label FOUND
    return (:found, s)
end

TESTDATA = [
    (f_copy, ==, 1:10, false),
    (f_sum, ===, 55, true),
    (f_filter_sum, ===, 25, true),
    (f_sum_nested_loop, ===, 220, true),
    (f_sum_update, ===, 50, true),
    (f_sum_op_init, ===, 50, true),
    (f_count_update, ===, 5, true),
    (f_count_op_init, ===, 5, true),
    (f_sum_continue, ===, 10, true),
    (f_sum_break, ===, 6, true),
    (f_find_return, ===, (:found, 3), true),
    (f_find_goto, ===, (:found, 3), true),
]

function test()
    @testset "$(args[1])" for args in TESTDATA
        test(args...)
    end
end

function test(f, ≛, desired, distributed)
    # Make sure that `executor` is used
    err = try
        f("string is not executor")
        nothing
    catch err
        @debug("Expected exception from `$f(nothing)`", exception = (err, catch_backtrace()))
        err
    end
    @test err isa MethodError
    # `maybe_set_simd` is happened to be the first function that
    # touches executor:
    @test err.f === FLoops._fold

    @test f(SequentialEx()) ≛ desired
    @test f(SequentialEx(simd = true)) ≛ desired
    @test f(ThreadedEx()) ≛ desired
    @testset for basesize in 2:10
        @test f(ThreadedEx(basesize = 2)) ≛ desired
    end
    distributed || return
    @test f(DistributedEx()) ≛ desired
    @testset for threads_basesize in 2:10
        @test f(DistributedEx(threads_basesize = threads_basesize)) ≛ desired
    end
end

end  # module
