module BenchParallelTriangularSum

using BenchmarkTools
using FLoops

# This is a rather contrived example for exploring the problems with
# which `nestlevel > 1` is useful.
function sum_triangular(exc, xs, f = f)
    init = zero(eltype(xs))
    @floop exc for a0 in xs,
        a1 in f(a0),
        a2 in f(a1),
        a3 in f(a2),
        a4 in f(a2),
        a5 in f(a2),
        a6 in f(a2),
        a7 in f(a2),
        a8 in f(a2),
        a9 in f(a2)

        m = a0 * a1 * a2 * a3 * a4 * a5 * a6 * a7 * a8 * a9
        @reduce(s = init + m)
    end
    return s
end

const SUITE = BenchmarkGroup()

f(x) = 1:x
xs = 1:8
SUITE["threaded"] = @benchmarkable sum_triangular(ThreadedEx(), $xs)
let s1 = SUITE["threaded_nest"] = BenchmarkGroup()
    for nestlevel in 1:3
        s1[:nestlevel=>nestlevel] = @benchmarkable sum_triangular(
            ThreadedEx(basesize = 1, nestlevel = $(Val(nestlevel))),
            $xs,
        )
    end
end
SUITE["sequential"] = @benchmarkable sum_triangular(SequentialEx(), $xs)

end  # module
BenchParallelTriangularSum.SUITE
