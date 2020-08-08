module BenchParallelFindMinMax

using BenchmarkTools
using FLoops

function findminmax(exc, xs)
    @floop exc for (i, x) in pairs(xs)
        @reduce() do (imin; i), (xmin; x)
            if isless(x, xmin)
                xmin = x
                imin = i
            end
        end
        @reduce() do (imax; i), (xmax; x)
            if isless(xmax, x)
                xmax = x
                imax = i
            end
        end
    end
    return ((xmin, imin), (xmax, imax))
end

const SUITE = BenchmarkGroup()

xs = rand(100_000)
SUITE["threaded"] = @benchmarkable findminmax(ThreadedEx(), $xs)
SUITE["sequential"] = @benchmarkable findminmax(SequentialEx(), $xs)

end  # module
BenchParallelFindMinMax.SUITE
