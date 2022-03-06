# Frequently asked questions

## [How to avoid boxing?](@id avoid-boxing)

Moved to: [How to avoid boxing?](@ref avoid-box)

## [What is the difference of `@reduce` and `@init` to the approach using `state[threadid()]`?](@id faq-state-threadid)

It is important to understand that `state[threadid()] += f(x)` may contain a
concurrency bug. If `f` can yield to the scheduler (e.g., containing an I/O
such as `println` and `@debug`), this code may not work as you expect, even
in a single-threaded `julia` instance and/or pre-1.3 Julia. This is because
the above code is equivalent to

```julia
i = threadid()
a = state[i]
b = f(x)
c = a + b
state[i] = c
```

If `f` can yield to the scheduler, and if there are other tasks with the same
`threadid` that can mutate `state`, the value stored at `state[threadid()]`
may not be equal to `a` by the time the last line is executed.

Furthermore, if `julia` supports migration of `Task` across OS threads at
some future version, the above scenario can happen even if `f` never yields
to the scheduler. Therefore, reduction or private state handling using
`threadid` is very discouraged.

This caveat does not apply to `@reduce` and `@init` used in FLoops.jl and in
general to the reduction mechanism used by JuliaFolds packages. Furthermore,
since `@reduce` and `@init` do not depend on a particular execution mechanism
(i.e., threading), `@floop` can generate the code that can be efficiently
executed in distributed and GPU executors.

!!! note

    The problem discussed above can also be worked around by, e.g., using
    `Threads.@threads for` (since it spawns exactly `nthreads()` tasks and
    ensures that each task is scheduled on each OS thread, as of Julia 1.6)
    and making sure that `state` is not shared across multiple loops.

## [How is a parallel `@floop` executed? What is the scheduling strategy?](@id faq-exeuctor)

It depends on the exact [executor](@ref executor) used. For example, a
parallel loop can be executed in a single thread by using `SequentialEx`
executor. (Thus, a "parallel loop" should really be called a
paralleliz**able** loop. But it is mouthful so we use the phrase "parallel
loop".) Furthermore, the default executor is determined by the input
collection types; e.g., if
[FoldsCUDA.jl](https://github.com/JuliaFolds/FoldsCUDA.jl) is loaded,
reductions on `CuArray` are executed on GPU with `CUDAEx` executor.

But, by default (i.e., if no special executor is registered for the input
collection type), parallel loops are run with `ThreadedEx` executor. How this
executor works is an implementation detail. However, as of writing
(Transducers.jl 0.4.60), this executor takes a divide-and-conquer approach.
That is to say, it first recursively halves the input collection until the
each part (base case) is smaller or equal to `basesize`. Each base case is
then executed in a single `Task`. The results of base cases are then combined
pair-wise in distinct `Task`s (re-using the ones created for reducing the
base case). Compared to the sequential scheduling approach taken by
`Threads.@threads for` (as of Julia 1.6), this approach has an advantage that
it exhibits a greater
[parallelism](https://www.cprogramming.com/parallelism.html).

If the scheduling by `ThreadedEx` does not yield a desired behavior, you can
use [FoldsThreads.jl](https://github.com/JuliaFolds/FoldsThreads.jl) for
different executors with different performance characteristics.
