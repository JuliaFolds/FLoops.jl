# [Parallel loops](@id tutorials-parallel)

`@floop` supports parallel loops not only for side-effect (as in
`Threads.@threads`) but also for complex reductions using the optional
`@combine` and `@reduce` syntax.

!!! note

    This tutorial can be read without reading the subsections with "Advanced:"
    prefix.

If you already know how `mapreduce` works,  [Relation to `mapreduce`](@ref
floop-and-mapreduce) may be the best first step for understanding the `@floop`
syntax.

## Independent execution

For in-place update operations (i.e., `Threads.@threads`-like operations),
you can use `@floop ThreadedEx() for`:

```jldoctest
julia> using FLoops

julia> function floop_map!(f, ys, xs, ex = ThreadedEx())
           @floop ex for i in eachindex(ys, xs)
               @inbounds ys[i] = f(xs[i])
           end
           return ys
       end;

julia> floop_map!(x -> x + 1, zeros(3), 1:3)
3-element Vector{Float64}:
 2.0
 3.0
 4.0
```

## Reduction using `@reduce acc ⊗= x` syntax

For a parallel algorithm that requires reductions, you can use `@reduce acc ⊗=
x` syntax:

```jldoctest
julia> using FLoops

julia> @floop for (x, y) in zip(1:3, 1:2:6)
           a = x + y
           b = x - y
           @reduce s += a
           @reduce t += b
       end
       (s, t)
(15, -3)
```

## Combining explicit sequential reduction results using `@combine`

FLoops.jl parallelizes a given loop by dividing the iteration space into
*basecases* and then execute the serial reduction on each basecase.  These
sub-results are combined using the function specified by `@combine` or
`@reduce` syntax.

!!! note

    Exactly how the executor schedules the basecases and the computation for
    combining them depends on the type (e.g., threads/GPU/distributed) and the
    scheduling options.  However, the loop using `@floop` works with all of them
    provided that `@combine` and `@reduce` define associative function.

```jldoctest
julia> using FLoops

julia> pidigits = string(BigFloat(π; precision = 2^20))[3:end];

julia> @floop begin
           @init hist = zeros(Int, 10)
           for char in pidigits
               n = char - '0'
               hist[n+1] += 1
           end
           @combine hist .+= _  # combine two histograms
       end
       hist
```

!!! note

    Above example uses string to show that FLoops.jl (and also other JuliaFolds
    packages) support strings.  But this is of course not a very good format for
    playing with the digits of pi.

We use syntax `@floop begin ... end` rather than `@floop for ... end` as the
former has the room for placing `@combine` after the `for` loop.  The syntaxes

    @combine acc ⊗= _
    @combine acc = _ ⊗ _

specifies that the reduction results are combined using the binary operator `⊗`
(e.g., `⊗ = (a, b) -> a .+ b` in the above code).  Suppose that we have `acc₁`
as the result of the reduction named `acc` for the first basecase and `acc₂` for
the second basecase.  These results are combined using

    acc₁ ⊗ acc₂

This result is combined with the other reduction results from the adjacent
(combined) results using the function `⊗` until we have the single result
corresponding to the reduction `acc` of entire iteration space.

Note that initialization must be prefixed by `@init`.  This is for signifying
that this initialization is local to the base case.  In particular, the
initialization may (and typically does) happen multiple times since there are
multiple basecases executed on different Julia tasks.

Only the variables specified by `@init` can be `@combine`d.  However, not all
`@init`'ed variables have to be combined.  For example, `@init` can be used for
allocating local buffer for intermediate computation.  See: [Local buffers using
`@init`](@ref local-buffer).

## Advanced: Unifying sequential and cross-basecase reductions

To accumulate numbers into a vector, we can use `push!` in the basecase and
combine the vectors from different basecases using `append!`.

```jldoctest
julia> using FLoops

julia> @floop begin
           @init odds = Int[]
           @init evens = Int[]
           for x in 1:5
               if isodd(x)
                   push!(odds, x)
               else
                   push!(evens, x)
               end
           end
           @combine odds = append!(_, _)
           @combine evens = append!(_, _)
       end
       (odds, evens)
([1, 3, 5], [2, 4])
```

Although this code works without an issue, it is redundant to use `push!` and
`append!` in this example.  Since `push!(xs, x)` and `append!(xs, [x])` are
equivalent, these functions are quite similar.  The intermediate value `[x]` is
referred to as a *singleton solution* because it is the value that would be used
if the input collection to the `for` loop contain only one item.

Indeed, once we have the singleton solution, we can simplify the above code by
using the syntax

    @reduce acc = op(init, input)

The expression `init` in the first argument position specifies how to initialize
the reduction result `acc`.  The expression `input` specifies the value defined
in the loop body which is accumulated into the reduction result `acc`.  The
current accumulation state `acc` is updated by

    acc = op(acc, input)

Using this notation, the above code can be simplified to

```jldoctest
julia> using FLoops

julia> @floop for x in 1:5
           ys = [x]  # "singleton solution"
           if isodd(x)
               @reduce odds = append!(Int[], ys)
           else
               @reduce evens = append!(Int[], ys)
           end
       end
       (odds, evens)
([1, 3, 5], [2, 4])
```

### Advanced: Handling unknown element types

In the above code, we assumed that we know the type of the elements that are
accumulated into a vector.  However, when writing generic code, it is often
impossible to know the element types in advance.  We can use BangBang.jl and
MicroCollections.jl to create a vector of items with unknown types in such a way
that the compiler can optimize very well.

```jldoctest
julia> using FLoops

julia> using BangBang  # for `append!!`

julia> using MicroCollections  # for `EmptyVector` and `SingletonVector`

julia> @floop for x in 1:5
           ys = SingletonVector(x)
           if isodd(x)
               @reduce odds = append!!(EmptyVector(), ys)
           else
               @reduce evens = append!!(EmptyVector(), ys)
           end
       end
       (odds, evens)
([1, 3, 5], [2, 4])
```

### Advanced: Initialization with `@reduce(acc = init op x)` syntax

When `op` is a binary operator, the infix syntax `acc = init op x` can
also be used:

```jldoctest
julia> using FLoops

julia> @floop for (x, y) in zip(1:3, 1:2:6)
           a = x + y
           b = x - y
           @reduce(s = 0im + a, t = 0im + b)
       end
       (s, t)
(15 + 0im, -3 + 0im)
```

**NOTE**: In the above examples, statements like `odds =
append!!(EmptyVector(), ys)` and `s = 0im + a` are *not* evaluated for
each iteration.  These statements as-is are evaluated only for the
first iteration (for each basecase) and then the expressions where the
first argument is replaced by the corresponding LHS, i.e., `odds =
append!!(odds, ys)` and `s = s + a`, are evaluated for the bulk of the
loop.

## [Local buffers using `@init`](@id local-buffer)

`@init` can be used without the reduction syntaxes.  It is useful when some
basecase-local buffers are required (for avoiding data races):

```jldoctest
julia> using FLoops

julia> ys = zeros(5)

julia> @floop begin
           @init buffer = zeros(100)
           for i in 1:5
               buffer .= sin.(i .* range(0, pi; length = length(buffer)))
               ys[i] = sum(buffer)
           end
       end
```

!!! note

    `@init` can also be used inside of the `for` loop body with the `@floop for`
    syntax as in

    ```julia
    @floop for i in 1:5
        @init buffer = zeros(100)
        buffer .= sin.(i .* range(0, pi; length = length(buffer)))
        ys[i] = sum(buffer)
    end
    ```

    However, `@floop begin ... end` syntax is recommended.

## Executing code at the end of basecase

On GPU, the reduction result must be an immutable value (and not contain
GC-manged objects).  Thus, we can use `SVector` for a histogram with a small
number of bins.  However, indexing update on `SVector` is very inefficient
compared to `MVector`.  Thus, it is better to execute the basecase reduction
using `MVector` while the cross-basecase reduction uses `SVector`.  This
transformation be done by inserting the code after the `for` loop and before the
`@combine` expression.

```jldoctest
julia> using FLoops

julia> using StaticArrays

julia> pidigits = string(BigFloat(π; precision = 2^20))[3:end];

julia> @floop begin
           @init buf = zero(MVector{10,Int32})
           for char in pidigits
               n = char - '0'
               buf[n+1] += 1
           end
           hist = SVector(buf)
           @combine hist .+= _
       end
       hist
```

!!! note

    To run this on GPU, specific executor library like FoldsCUDA.jl has to be
    used.  Furthermore, `pidigits` has to be transformed into a GPU-compatible
    format (e.g., `CuVector{Int8}`).

## Advanced: Complex reduction with `@reduce() do` syntax

For more complex reduction, use `@reduce() do` syntax:

```jldoctest
julia> using FLoops

julia> @floop for (i, v) in pairs([0, 1, 3, 2]), (j, w) in pairs([3, 1, 5])
           d = abs(v - w)
           @reduce() do (dmax = -1; d), (imax = 0; i), (jmax = 0; j)
               if isless(dmax, d)
                   dmax = d
                   imax = i
                   jmax = j
               end
           end
       end
       (dmax, imax, jmax)
(5, 1, 3)
```

### Advanced: How to read a loop with `@reduce() do` syntax

When reading code with `@reduce() do`, a quick way to understand it is
to mentally comment out the line with `@reduce() do` and the
corresponding `end`.  To get a full picture, move the initialization
parts (in the above example, `dmax = -1`, `imax = 0`, and `jmax = 0`)
to outside `for` loop:

```jldoctest
julia> using FLoops

julia> let
           dmax = -1  # -+
           imax = 0   #  | initializers
           jmax = 0   # -+
           for (i, v) in pairs([0, 1, 3, 2]), (j, w) in pairs([3, 1, 5])
               d = abs(v - w)
               if isless(dmax, d)  # -+
                   dmax = d        #  | `do` block body
                   imax = i        #  |
                   jmax = j        #  |
               end                 # -+
           end
           (dmax, imax, jmax)
       end
(5, 1, 3)
```

This exact transformation is used for defining the sequential
basecase.  Consecutive basecases are combined using the code in the
`do` block body.

## Control flow syntaxes

Control flow syntaxes such as `continue`, `break`, `return`, and
`@goto` work with parallel loops:

```jldoctest
julia> using FLoops

julia> @floop for x in 1:10
           y = 2x
           @reduce() do (s; y)
               s = y
           end
           x == 3 && break
       end
       s
6
```

`@reduce` can be used multiple times in a loop body

```jldoctest
julia> using FLoops

julia> @floop for (i, v) in pairs([0, 1, 3, 2])
           y = 2v
           @reduce() do (ymax; y), (imax; i)
               if isless(ymax, y)
                   ymax = y
                   imax = i
               end
           end
           @reduce() do (ymin; y), (imin; i)
               if isless(y, ymin)
                   ymin = y
                   imin = i
               end
           end
       end
       (ymax, imax), (ymin, imin)
((6, 3), (0, 1))
```

## [Executors](@id tutorials-executor)

`@floop` takes optional executor argument to specify an execution strategies
and the parameters of the strategy:

```jldoctest
julia> using FLoops

julia> function demo(executor)
           @floop executor for x in 1:10
               @reduce(s += x)
           end
           return s
       end;

julia> demo(SequentialEx(simd = Val(true)))
55

julia> demo(ThreadedEx(basesize = 2))
55

julia> demo(DistributedEx(threads_basesize = 2))
55
```

This is in particular useful for the trick to ["change" the number of threads
without restarting `julia` using `basesize`
option](https://juliafolds.github.io/data-parallelism/howto/faq/#set-nthreads-at-run-time).

JuliaFolds provides additional executors:

* [FoldsThreads.jl](https://github.com/JuliaFolds/FoldsThreads.jl) provides a
  rich set of thread-based executors.
* [FoldsCUDA.jl](https://github.com/JuliaFolds/FoldsCUDA.jl) provides
  `CUDAEx` for executing the parallel loop on GPU.

## [Advanced: Relation to `mapreduce`](@id floop-and-mapreduce)

If you know are familar with functional style data parallel API and already know
`mapreduce(f, op, xs; init)` works, it is worth noting that `@floop` is, *as a
very rough approximation*, a way to invoke `acc = mapreduce(f, op, xs; init)`
with a custom syntax

```julia
@floop for x in xs
    y = f(x)
    @reduce acc = op(init, y)
end
```

or

```julia
@floop begin
    @combine acc = init
    for x in xs
        y = f(x)
        acc = op(acc, y)
    end
    @combine acc = op(_, _)
end
```

However, as explained above, `@floop` supports various constructs that are not
directly supported by `mapreduce`.  To fully cover the semantics of `@floop` in
a functional manner, the extended reduction ("fold") protocol of
[Transducers.jl](https://github.com/JuliaFolds/Transducers.jl) is required.  In
fact, FLoops.jl is simply a syntax sugar for invoking the reductions defined in
Transducers.jl.
