# FLoops: `fold` for humans™

[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://juliafolds.github.io/FLoops.jl/dev)
[![GitHub Actions](https://github.com/JuliaFolds/FLoops.jl/workflows/Run%20tests/badge.svg)](https://github.com/JuliaFolds/FLoops.jl/actions?query=workflow%3A%22Run+tests%22)

[FLoops.jl](https://github.com/JuliaFolds/FLoops.jl) provides a macro
`@floop`. It can be used to generate a fast generic sequential and parallel
iteration over complex collections.

Furthermore, the loop written in `@floop` can be executed with any compatible
[executors](https://juliafolds.github.io/FLoops.jl/dev/tutorials/parallel/#tutorials-executor).
See [FoldsThreads.jl](https://github.com/JuliaFolds/FoldsThreads.jl) for
various thread-based executors that are optimized for different kinds of
loops. [FoldsCUDA.jl](https://github.com/JuliaFolds/FoldsCUDA.jl) provides an
executor for GPU. FLoops.jl also provide a simple distributed executor.

## Update notes

FLoops.jl 0.2 defaults to a parallel loop; i.e., it uses a parallel executor
(e.g., `ThreadedEx`) when the executor is not specified and the explicit
sequential form `@floop begin ...  end` is not used.

That is to say, `@floop` without `@reduce` such as

```JULIA
@floop for i in eachindex(ys, xs)
    ys[i] = f(xs[i])
end
```

is now executed in parallel by default.

## Usage

# Parallel loop

`@floop` is a superset of `Threads.@threads` (see below) and in particular
supports complex reduction with additional syntax `@reduce`:

```julia
julia> @floop for (x, y) in zip(1:3, 1:2:6)
           a = x + y
           b = x - y
           @reduce s += a
           @reduce t += b
       end
       (s, t)
(15, -3)
```

For more examples, see
[parallel loops tutorial](https://juliafolds.github.io/FLoops.jl/dev/tutorials/parallel/).

# Sequential (single-thread) loop

Simply wrap a `for` loop and its initialization part with `@floop begin ... end`:

```julia
julia> using FLoops  # exports @floop macro

julia> @floop begin
           s = 0
           for x in 1:3
               s += x
           end
       end
       s
6
```

For more examples, see
[sequential loops tutorial](https://juliafolds.github.io/FLoops.jl/dev/tutorials/sequential/).

## Advantages over `Threads.@threads`

`@floop` is a superset of `Threads.@threads` and has a couple of advantages:

* `@floop` supports various input collection types including
  arrays, dicts, sets, strings, and many iterators from `Base.Iterators` such
  as `zip` and `product`. More precisely, `@floop` can generate high-performance
  parallel iterations for any collections that supports
  [SplittablesBase.jl](https://github.com/JuliaFolds/SplittablesBase.jl)
  interface.
* With [`FoldsThreads.NondeterministicEx`](https://juliafolds.github.io/FoldsThreads.jl/dev/#FoldsThreads.NondeterministicEx),
  `@floop` can even parallelize iterations over non-parallelizable input collections
  (although it is beneficial only for heavier workload).
* [FoldsThreads.jl](https://github.com/JuliaFolds/FoldsThreads.jl) provides
  multiple alternative thread-based executors (= loop execution backend) that
  can be used to tune the performance without touching the loop itself.
* [FoldsCUDA.jl](https://github.com/JuliaFolds/FoldsCUDA.jl) provides a simple
  GPU executor.
* `@reduce` syntax for supporting complex reduction in a forward-compatible manner
  * Note: `threadid`-based reduction (that is commonly used in conjunction with
    `@threads`) may not be forward-compatible to Julia that supports
    migrating tasks across threads.
* There is a trick for ["changing" the effective number of threads without
  restarting `julia` using the `basesize`
  option](https://juliafolds.github.io/data-parallelism/howto/faq/#set-nthreads-at-run-time).

The relative disadvantages may be that `@floop` is much newer than
`Threads.@threads` and has much more flexible internals. These points can
contribute to undiscovered bugs.

## How it works

`@floop` works by converting the native Julia `for` loop syntax to
`foldl` defined by
[Transducers.jl](https://github.com/JuliaFolds/Transducers.jl).  Unlike
`foldl` defined in `Base`, `foldl` defined by Transducers.jl is
[powerful enough to cover the `for` loop semantics and more](https://juliafolds.github.io/Transducers.jl/dev/reference/manual/#Base.foreach).
