# # How to write _X_ in parallel.

using FLoops

using LiterateTest                                                     #src
using Test                                                             #src

# ## In-place mutation
#
# Mutable containers can be allocated in the `init` expressions
# (`zeros(3)` in the example below):

@test begin
    local ys  # hide
    @floop for x in 1:10
        xs = [x, 2x, 3x]
        @reduce() do (ys = zeros(3); xs)
            ys .+= xs
        end
    end
    ys
end == [55, 110, 165]

# Mutating objects allocated in the `init` expressions is not data
# race because each basecase "owns" such mutable objects.  However, it
# is incorrect to mutate objects created outside `init` expressions.
#
# !!! note
#
#     Technically, it is correct to mutate objects in the loop body if
#     the objects are protected by a lock.  However, it means that the
#     code block protected by the lock can only be executed by a
#     single task.  For efficient data parallel loops, it is highly
#     recommended to use **non**-thread-safe data collection (i.e., no
#     lock) and construct the `@reduce` block that efficiently merge
#     two mutable objects.

# ### INCORRECT EXAMPLE

# This example has data race because the array `ys0` is shared across
# all base cases and mutated in parallel.

ys0 = zeros(3)
@dedent let
    @floop for x in 1:10
        xs = [x, 2x, 3x]
        @reduce() do (ys = ys0; xs)
            ys .+= xs
        end
    end
end

# ## [Data race-free reuse of mutable objects using private variables](@id private-variables)
#
# To avoid allocation for each iteration, it is useful to pre-allocate mutable
# objects and reuse them. We can use [`@init`](@ref) macro to do this in a
# data race-free ("thread-safe") manner:

@test begin
    local ys  # hide
    @floop for x in 1:10
        @init xs = Vector{typeof(x)}(undef, 3)
        xs .= (x, 2x, 3x)
        @reduce() do (ys = zeros(3); xs)
            ys .+= xs
        end
    end
    ys
end == [55, 110, 165]

# ## Efficient and reproducible usage patterns of random number generators
#
# Julia's default random number generator (RNG) is data race-free for invoking
# from multiple threads; i.e., calls like `randn()` have well-defined
# behaviors. However, for the performance and reproducibility, it is useful to
# directly creating the RNGs. A convenient approach to this is to use a
# [private variable](@ref private-variables):

using Random

MersenneTwister()  # the first invocation of `MersenneTwister` is not thread-safe

@dedent let
    @floop for _ in 1:10
        @init rng = MersenneTwister()
        @reduce(s += rand(rng))
    end
end

# The above approach may work well for exploratory purposes. However, it has a
# problem that the computation is not reproducible and each invocation of
# `MersenneTwister` requires an I/O (reading `/dev/urandom`). These problems
# can be solved by, for example, using `randjump` function. First, let us
# construct `ntasks` RNGs to be used.

using Future

ntasks = Threads.nthreads()  # the number of base cases
rngs = [MersenneTwister(123456789)]
let rng = rngs[end]
    for _ in 2:ntasks
        rng = Future.randjump(rng, big(10)^20)
        push!(rngs, rng)
    end
end

# This list of RNGs can be used with some input array by manually partitioning
# the input into `ntasks` chunks:

@dedent let
    xs = 1:10  # input
    chunks = Iterators.partition(xs, cld(length(xs), length(rngs)))
    @floop ThreadedEx(basesize = 1) for (rng, chnk) in zip(rngs, chunks)
        y = 0
        for _ in chnk
            y += rand(rng)
        end
        @reduce(s += y)
    end
end

# Note that the above pattern can also be used with `@threads for` loop.
#
# Another approach is to use a counter-based RNG as illustrated in
# [Monte-Carlo π · FoldsCUDA](https://juliafolds.github.io/FoldsCUDA.jl/dev/examples/monte_carlo_pi/).
# This approach works both on CPU and GPU.
