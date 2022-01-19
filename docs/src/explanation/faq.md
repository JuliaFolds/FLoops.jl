# Frequently asked questions

## [How to avoid boxing?](@id avoid-boxing)

FLoops.jl may complain about `HasBoxedVariableError`. For a quick prototyping,
calling [`FLoops.assistant(false)`](@ref FLoops.assistant) to disable the
error/warning may be useful.  However, it is also easy to avoid this problem if
you understand a few patterns as explained below:

* ["Leaked variables" ⇒ use `local`](@ref leaked-variables)
* ["Uncertain values" ⇒ use `let`](@ref uncertain-values)
* ["Not really a data race" ⇒ use `Ref`](@ref not-really-a-data-race)

### ["Leaked variables" ⇒ use `local`](@id leaked-variables)

`HasBoxedVariableError` can occur when "leaked" variables are causing data
races.  Consider the following example:

```julia
function leaked_variable_example(xs)
    a = xs[begin]
    b = xs[end]
    c = (a + b) / 2
    @floop for x in xs
        a = max(x, c)
        @reduce s += a
    end
    return s
end
```

Calling this function causes `HasBoxedVariableError`:

```julia-console
julia> FLoops.assistant(:error);

julia> leaked_variable_example(1:2)
ERROR: HasBoxedVariableError: Closure ... has 1 boxed variable: a
```

This occurs because the variable `a` is assigned before `@floop` by `a =
xs[begin]` and inside `@floop` by `a = max(x, c)`.  However, since the
assignment inside `@floop` can occur in parallel, this is a data race.  We can
avoid this issue easily by making `a` local inside the loop:

```julia
function leaked_variable_example_fix1(xs)
    a = xs[begin]
    b = xs[end]
    c = (a + b) / 2
    @floop for x in xs
        local a = max(x, c)   # note `local`
        @reduce s += a
    end
    return s
end
```

Alternatively, we can use a different name:

```julia
function leaked_variable_example_fix2(xs)
    a = xs[begin]
    b = xs[end]
    c = (a + b) / 2
    @floop for x in xs
        d = max(x, c)   # not `a`
        @reduce s += d
    end
    return s
end
```

or limit the scope of `a` used for calculating `c`:

```julia
function leaked_variable_example_fix3(xs)
    c = let a = xs[begin], b = xs[end]  # limit the scope of `a`
        (a + b) / 2
    end
    @floop for x in xs
        a = max(x, c)
        @reduce s += a
    end
    return s
end
```

### ["Uncertain values" ⇒ use `let`](@id uncertain-values)

!!! note
    This is a known limitation as of Julia 1.8-DEV. This documentation may not
    be accurate in the future version of Julia. For more information, see:
    [performance of captured variables in closures · Issue #15276 · JuliaLang/julia](https://github.com/JuliaLang/julia/issues/15276)

`HasBoxedVariableError` can also occur when Julia is uncertain about the value
of some variables in the scope surrounding `@floop` (i.e., there are multiple
binding locations).  For example:

```julia
function uncertain_value_example(xs; flag = false)
    if flag
        a = 0
    else
        a = 1
    end
    @floop for x in xs
        x += a
        @reduce s += x
    end
    return s
end
```

This can be fixed by using `let` to ensure that the variable `a` does not change
while executing `@floop`. (Julia can be sure that the variable is not updated
when it is assigned only once.)

```julia
function uncertain_value_example_fix(xs; flag = false)
    if flag
        a = 0
    else
        a = 1
    end
    let a = a  # "quench" the value of `a`
        @floop for x in xs
            x += a
            @reduce s += x
        end
        return s
    end
end
```

### ["Not really a data race" ⇒ use `Ref`](@id not-really-a-data-race)

It is conceptually sound to assign to the variables in an outer scope of
`@floop` if it is ensured that the race does not occur.  For example, in the
following example, `found = i` can be executed at most once since the elements
of `xs` are all distinct:

```julia
function non_data_race_example(xs::UnitRange; ex = nothing)
    local found = nothing
    @floop ex for (i, x) in pairs(xs)
        if x == 1
            found = i
        end
    end
    return found
end
```

However, FLoops.jl also complains about `HasBoxedVariableError` when executing
this function.  We can fix this by using `Ref`:

```julia
function non_data_race_example_fix(xs::UnitRange; ex = nothing)
    found = Ref{Union{Int,Nothing}}(nothing)
    @floop ex for (i, x) in pairs(xs)
        if x == 1
            found[] = i
        end
    end
    return found[]
end
```

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
