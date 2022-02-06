# [Parallel loops](@id tutorials-parallel)

`@floop` supports parallel loops not only for side-effect (as in
`Threads.@threads`) but also for complex reductions using the `@combine` and
`@reduce` macros.

If you already know how `mapreduce` works,  [Relation to `mapreduce`](@ref
floop-and-mapreduce) may be the best first step for understanding the `@floop`
syntax.

```@contents
Pages = ["parallel.md"]
Depth = 3
```

!!! note
    This tutorial can be read without reading the subsections with "Advanced:"
    prefix.

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
           @init hist = zeros(Int, 10)  # (1) initialization
           for char in pidigits         # (2) basecase
               n = char - '0'
               hist[n+1] += 1
           end
           @combine hist .= hist .+ _   # (3) combine
           # Or, use a short hand notation:
           #     @combine hist .= _
       end
       hist
10-element Vector{Int64}:
 31559
 31597
 31392
 31712
 31407
 31835
 31530
 31807
 31469
 31345
```

!!! note

    Above example uses string to show that FLoops.jl (and also other JuliaFolds
    packages) support strings.  But this is of course not a very good format for
    playing with the digits of pi.

_Conceptually_, this produces a program that acts like (but is more optimized
than) the following code:

```julia
# `chunks` is prepared such that:
@assert pidigits == reduce(vcat, chunks)
# i.e., pidigits == [chunks[1]; chunks[2]; ...; chunks[end]]

hists = Vector{Any}(undef, length(chunks))
@sync for (i, pidigitsᵢ) in enumerate(chunks)
    @spawn begin
        local hist = zeros(Int, 10)   # (1) initialization
        for char in pidigitsᵢ         # (2) basecase
            n = char - '0'
            hist[n+1] += 1
        end
        hists[i] = hist               # "sub-solution" of this basecase
    end
end
hist = hists[1]
for hist′ in hists[2:end]
    hist .= hist .+ hist′             # (3) combine the sub-solutions
end
```

(1) The basecase-local accumulators are initialized using the [`@init`](@ref)
statements.

(2) Each basecase loop is executed with its own local accumulators.

(3) The sub-solutions `hists` are combined using the expression specified by
`@combine`.  In the above pseudo code, given the expression `hist .= hist .+ _`
(or equivalently `hist .+= _`), the symbol `hist` is substituted by the
sub-solution `hist` of the first basecase and the symbol `_` is substituted by
the sub-solution `hist` of the second basecase.  Evaluation of this expression
produces a sub-solution `hist` combining the first and the second basecases.
The sub-solution of the third and later basecases are combined into `hist` using
the same procedure.

In general, the expression

```julia
@combine acc = op(acc, _)
```

indicates that a sub-solution `acc` computed for a certain subset of the input
collection (e.g., `pidigits` in the example) is combined with the sub-solution
`acc_right` using

```julia
acc = op(acc, acc_right)
```

The binary function/operator `op` must be
[associative](https://en.wikipedia.org/wiki/Associative_property).  However,
`op` does not have to be side-effect-free.  In fact, if invoking in-place
`op` on the sob-solutions does not cause thread safety issues, there is no
problem in using in-place mutation.  For example, the above usage of `@combine
hist .= hist .+ _` is correct because `hist` is created for each basecase; i.e.,
no combine step can mutate the vector `hist` while other combine step tries to
read from or write to the same vector.

!!! warning
    All three pieces of the above `@floop begin ... end` code (i.e., (1) `@init
    ...`, (2) `for`-loop body, and (3) `@combine ...`) _may_ (and likely will)
    be executed concurrently.  Thus, **they must be written in such a way that
    concurrent execution in _arbitrary number_ of tasks is correct** (e.g., no
    data race is possible).  In particular, the above pseudo code is inaccurate
    in that it executes the `@combine` expression serially.  This is typically
    not guaranteed by the [executor](@ref tutorials-executor) provided by
    JuliaFolds.

!!! note
    The combine steps of the above pseudo code is different from how most of the
    executors in JuliaFolds execute FLoops.jl.  Typically, the combine steps are
    executed in parallel; i.e., they use a more tree-like fashion to provide a
    greater amount of
    [_parallelism_](https://www.cprogramming.com/parallelism.html).

Only the variables available "after" the `for` loop (but not the variables local
to the loop body) can be used as the arguments to `@combine`.  Typically, it
means the symbols specified by `@init`.  However, it is possible to introduce
new variables for `@combine` by placing the code introducing new variables after
the `for` loop (see [Executing code at the end of basecase](@ref
simple-completebasecase)).  Note also that `@init`'ed variables do not have to
be `@combine`d.  For example, `@init` can be used for allocating local buffer
for intermediate computation (See: [Local buffers using `@init`](@ref
local-buffer)).

## Advanced: Understanding `@combine` in terms of `mapreduce`

Alternatively, a more concise way to understand `@floop` and `@combine` is to
conceptualized it as a lowering to a call to `mapreduce`:

```julia
function basecase(pidigitsᵢ)
    local hist = zeros(Int, 10)   # (1) initialization
    for char in pidigitsᵢ         # (2) basecase
        n = char - '0'
        hist[n+1] += 1
    end
    return hist
end

function combine!(hist, hist′)
    hist .= hist .+ hist′         # (3) combine the sub-solutions
    return hist
end

hist = mapreduce(basecase, combine!, chunks)
```

where `mapreduce` is a parallel implementation of `Base.mapreduce` (e.g.,
`Folds.mapreduce`). Although this picture still does not reflect the actual
internal of FLoops.jl (and Transducers.jl), this is a much more accurate mental
model than the pseudo code above.

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
           @combine odds = append!(odds, _)
           @combine evens = append!(evens, _)
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

```jldoctest
julia> let
           odds = Int[]   # \___  The expression in the first argument is
           evens = Int[]  # /     used for the initialization
           for x in 1:5
               ys = [x]
               if isodd(x)
                   odds = append!(odds, ys)
                   #             -----
                   #             LHS `odds` inserted to the first argument
               else
                   evens = append!(evens, ys)
                   #             -----
                   #             LHS `evens` inserted to the first argument
               end
           end
           (odds, evens)
       end
([1, 3, 5], [2, 4])
```

### Handling unknown element types

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

### Initialization with `@reduce(acc = init op x)` syntax

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

julia> ys = zeros(5);

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

## [Executing code at the end of basecase](@id simple-completebasecase)

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
10-element SVector{10, Int32} with indices SOneTo(10):
 31559
 31597
 31392
 31712
 31407
 31835
 31530
 31807
 31469
 31345
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
basecase.

Consecutive basecases are combined using the code in the `do` block body.  That
is to say, the accumulation result `acc = (dmax, imax, jmax)` from a basecase
and the accumulation result `acc_right = (dmax, imax, jmax)` from then next
basecase are combined using the following function

```julia
function combine(acc, acc_right)
    (dmax, imax, jmax) = acc  # left variables are bound to left sub-solutions
    (d, i, j) = acc_right     # right variables are bound to right sub-solutions
    if isless(dmax, d)
        dmax = d
        imax = i
        jmax = j
    end
    acc = (dmax, imax, jmax)
    return acc
end
```

Note that variables left to `;` and the variables right to `;` in the original
`@reduce() do` syntax are grouped into the left argument `acc` and the right
argument `acc_right`, respectively.  This is why the `@reduce() do` syntax uses
the nonstandard delimiter `;` for separating the arguments.  That is to say,
`@reduce() do` syntax "transposes" (or "unzips") the arguments to clarify the
correspondence of the left and the right arguments.  In general, the expression

```julia
@reduce() do (acc₁; x₁), (acc₂; x₂), ..., (accₙ; xₙ)
    $expression_updates_accs
end
```

generates the combine function

```julia
function combine((acc₁, acc₂, ..., accₙ), (x₁, x₂, ..., xₙ))
    $expression_updates_accs
    return (acc₁, acc₂, ..., accₙ)
end
```

(Aside: This also clarifies why `@reduce() do` doesn't use the standard argument
ordering `@reduce() do (acc₁, acc₂, ..., accₙ), (x₁, x₂, ..., xₙ)`.  From this
expression, it is very hard to tell `accᵢ` corresponds to `xᵢ`.)

Like other `@reduce` expressions, `@reduce() do` syntax can be used multiple
times in a loop body:

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

Since the variables left to `;` (i.e., `ymax`, `imax`, `ymin`, and `imin` in the
above example) are the "output" variables, they must be unique (otherwise, the
computation result is not available outside the loop).  However, the variables
right to `;` (i.e., `y` and `i` in the above example) do not have to be unique
because multiple reductions can be computed using the same intermediate
computation done in the loop body.

Similar to `@reduce() do` syntax, there is `@combine() do` syntax.  This is
useful when it is more straightforward to use different code for the basecase
and combine steps.

```jldoctest
julia> using FLoops

julia> function maybe_zero_extend_right!(hist, n)
           l = length(hist)
           if l < n
               resize!(hist, n)
               fill!(view(hist, l+1:n), 0)
           end
       end;

julia> function count_positive_ints(ints, ex = ThreadedEx())
           @floop ex begin
               @init hist = Int[]
               for n in ints
                   n > 0 || continue  # filter out non-positive integers
                   maybe_zero_extend_right!(hist, n)
                   @inbounds hist[n] += 1
               end
               @combine() do (hist; other)
                   n = length(other)
                   maybe_zero_extend_right!(hist, n)
                   @views hist[1:n] .+= other
               end
           end
           return hist
       end;

julia> count_positive_ints([7, 5, 3, 3, 8, 6, 0, 6, 5, 2, 6, 6, 5, 0, 8, 3, 4, 2, 5, 2])
8-element Vector{Int64}:
 0
 3
 3
 1
 4
 4
 1
 2
```

## Control flow syntaxes

Control flow syntaxes such as `continue`, `break`, `return`, and `@goto` work
with parallel loops, provided that they are used outside the `@reduce` syntax:

```jldoctest
julia> using FLoops

julia> function firstmatch(p, xs; ex = ThreadedEx())
           @floop ex for ix in pairs(xs)
               _i, x = ix
               if p(x)
                   @reduce() do (found = nothing; ix)
                       found = ix
                   end
                   break
               end
           end
           return found  # the *first* pair `i => x` s.t. `p(x)`
       end;

julia> firstmatch(==(42), 1:10)  # finds nothing

julia> firstmatch(isodd, [0, 2, 1, 1, 1])
3 => 1
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
    @init acc = init
    for x in xs
        y = f(x)
        acc = op(acc, y)
    end
    @combine acc = op(acc, _)
end
```

However, as explained above, `@floop` supports various constructs that are not
directly supported by `mapreduce`.  To fully cover the semantics of `@floop` in
a functional manner, the extended reduction ("fold") protocol of
[Transducers.jl](https://github.com/JuliaFolds/Transducers.jl) is required.  In
fact, FLoops.jl is simply a syntax sugar for invoking the reductions defined in
Transducers.jl.
