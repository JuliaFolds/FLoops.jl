"""
    @reduce() do (acc₁ [= init₁]; x₁), ..., (accₙ [= initₙ]; xₙ)
        ...
    end
    @reduce(acc₁ op₁= x₁, ..., accₙ opₙ= xₙ)
    @reduce(acc₁ = op₁(init₁, x₁), ..., accₙ = opₙ(initₙ, xₙ))

Declare how accumulators are updated in the sequential basecase and
how the resulting accumulators from two basecases are combined.

The arguments `accᵢ` and `xᵢ` must be symbols except for `xᵢ` of the
last two forms in which an expression can be used at `xᵢ`.

In the first form,

```julia
function ((acc₁, acc₂, ..., accₙ), (x₁, x₂, ..., xₙ))
    ...  # body of the `do` block
    return (acc₁, acc₂, ..., accₙ)
end
```

should be an associative function.

In the last two forms, every `opᵢ` should be an associative function.

If `initᵢ` is specified, the tuple `(init₁, init₂, ..., initₙ)` should
be the identify of the related associative function.  `accᵢ = initᵢ`
is evaluated for each basecase (each `Task`) in the beginning.

Consider a loop with the following form

```julia
@floop for ...
    # code computing (x₁, x₂, ..., xₙ)
    @reduce() do (acc₁ = init₁; x₁), ..., (accₙ = initₙ; xₙ)
        # code updating (acc₁, acc₂, ..., accₙ) using (x₁, x₂, ..., xₙ)
    end
end
```

This is converted to

```julia
acc₁ = init₁
...
accₙ = initₙ
for ...
    # code computing (x₁, x₂, ..., xₙ)
    # code updating (acc₁, acc₂, ..., accₙ) using (x₁, x₂, ..., xₙ)
end
```

for computing `(acc₁, acc₂, ..., accₙ)` of each basecase.  The
accumulators `accᵢ` of two basecases are combined using "code updating
`(acc₁, acc₂, ..., accₙ)` using `(x₁, x₂, ..., xₙ)`" where `(x₁, x₂,
..., xₙ)` are replaced with `(acc₁, acc₂, ..., accₙ)` of the next
basecase.  Note that "code computing `(x₁, x₂, ..., xₙ)`" is not used
for combining the basecases.

# Examples
```julia
@reduce() do (vmax=-Inf; v), (imax=0; i)
    if isless(vmax, v)
        vmax = v
        imax = i
    end
end

@reduce(s += y, p *= y)

@reduce(xs = append!!(EmptyVector(), x), ys = append!!(EmptyVector(), y))
```
"""
macro reduce(args...)
    # We insert a custom non-`Expr` object `ReduceOpSpec` in the AST
    # so that the argument to `@reduce` can be later analyzed by
    # `floop_parallel` below.  We do this because `floop_parallel` is
    # run after `macroexpand`.  We insert `throw` of `ReduceOpSpec` so
    # that unprocessed `ReduceOpSpec` becomes an error at runtime
    # rather than silently failing.
    :(throw($(ReduceOpSpec(collect(Any, args)))))
end
# TODO: detect free variables in `do` blocks

struct ReduceOpSpec
    args::Vector{Any}
end

function on_reduce_op_spec(on_spec, ex; on_expr = donothing, otherwise = donothing)
    @match ex begin
        Expr(:call, throw′, spec::ReduceOpSpec) => on_spec(spec.args)
        Expr(head, args...) => begin
            new_args = map(args) do x
                on_reduce_op_spec(on_spec, x; on_expr = on_expr, otherwise = otherwise)
            end
            on_expr(head, new_args...)
        end
        _ => otherwise(ex)
    end
end

on_reduce_op_spec_reconstructing(on_spec, ex) =
    on_reduce_op_spec(on_spec, ex; on_expr = Expr, otherwise = identity)

has_reduce(ex) = on_reduce_op_spec(
    _ -> true,
    ex;
    on_expr = (_, args...) -> any(args),
    otherwise = _ -> false,
)

function floop_parallel(ex::Expr, simd, executor = ThreadedEx())
    if !isexpr(ex, :for, 2)
        error("expected a `for` loop; got:\n", ex)
    end
    iterspec, body = ex.args
    parallel_loop_ex = @match iterspec begin
        Expr(:block, loop_axes...) => begin
            rf_arg, coll = transform_multi_loop(loop_axes)
            as_parallel_loop(rf_arg, coll, body, simd, executor)
        end
        Expr(:(=), rf_arg, coll) => begin
            as_parallel_loop(rf_arg, coll, body, simd, executor)
        end
    end
    return parallel_loop_ex
end

function analyze_rf_args(ex::Expr)
    @assert isexpr(ex, :tuple)
    accs = []
    inits = []
    inputs = []
    for arg in ex.args
        @match arg begin
            Expr(:block, acc_init, x) || Expr(:block, acc_init, ::LineNumberNode, x) =>
                begin
                    push!(inputs, x)
                    @match acc_init begin
                        Expr(:(=), a, i) => begin
                            push!(accs, a)
                            push!(inits, i)
                        end
                        a => push!(accs, a)
                    end
                end
            Expr(:tuple, a, x) => begin
                throw(ArgumentError("got `($a, $x)` use `($a; $x)` instead"))
            end
        end
    end
    if !isempty(inits) && length(inits) != length(inputs)
        # TODO: Remove this restriction.  If not all `init`s are
        # specified, use it only for the empty case.
        throw(ArgumentError(string(
            "[NOT IMPLEMENTED]",
            " Currently, initial value should be specified for all accumulators",
            " when it is specified for at least one accumulator.",
        )))
    end
    if isempty(inits)
        inits = nothing
    end
    return accs, inits, inputs
end

function verify_unique_symbols(all_vars, kind)
    if length(Set(all_vars)) != length(all_vars)
        counts = Dict{Any,Int}()
        for var in all_vars
            counts[var] = get(counts, var, 0) + 1
        end
        dups = sort!([(n, var) for (var, n) in counts if n > 1])
        msg = sprint() do io
            print(io, "Same $kind variable used multiple times.")
            for (n, var) in dups
                println(io)
                print(io, "* `", var, "` used ", n, " times")
            end
        end
        throw(ArgumentError(msg))
    end
end

# To allow something like `@reduce(c += 1)` and `@reduce(c = 0 + 1)`,
# assign the right (second) argument to a temporary variable:
function extract_pre_updates(raw_inputs)
    inputs = []
    pre_updates = []
    for x in raw_inputs
        if x isa Symbol
            push!(inputs, x)
        else
            @gensym tmp
            push!(pre_updates, :($tmp = $x))
            push!(inputs, tmp)
        end
    end
    return (inputs, pre_updates)
end

function as_parallel_loop(rf_arg, coll, body0::Expr, simd, executor)
    accs_symbols = Symbol[]
    inputs_symbols = Symbol[]
    init_exprs = []
    combine_bodies = []
    all_rf_accs = []
    all_rf_inputs = []
    body1 = on_reduce_op_spec_reconstructing(body0) do opspecs
        @gensym grouped_accs grouped_inputs
        push!(accs_symbols, grouped_accs)
        push!(inputs_symbols, grouped_inputs)
        if length(opspecs) == 1 && is_function(opspecs[1])
            # handle: @reduce() do ...
            rf_ex, = opspecs
            # rf_ex = :(((acc1; input1), ..., (accN; inputN)) -> rf_body)
            accs, inits, inputs = analyze_rf_args(rf_ex.args[1])
            rf_body = rf_ex.args[2]
            pre_updates = []
            updaters = [rf_body]
        else
            if all(is_rebinding_update, opspecs)
                # handle: @reduce(acc₁ op₁= x₁, ..., accₙ opₙ= xₙ)
                ops = [Symbol(String(x.head)[1:end-1]) for x in opspecs]
                accs = [x.args[1] for x in opspecs]
                inits = nothing
                (inputs, pre_updates) = extract_pre_updates([x.args[2] for x in opspecs])
            elseif all(x -> isexpr(x, :(=), 2) && isexpr(x.args[2], :call, 3), opspecs)
                # handle: @reduce(acc₁ = op₁(init₁, x₁), ..., accₙ = opₙ(initₙ, xₙ))
                ops = [x.args[2].args[1] for x in opspecs]
                accs = [x.args[1] for x in opspecs]
                inits = [x.args[2].args[2] for x in opspecs]
                (inputs, pre_updates) =
                    extract_pre_updates([x.args[2].args[3] for x in opspecs])
            else
                error(join(vcat(["unsupported:"], opspecs), "\n"))
            end
            updaters = [:($a = $op($a, $x)) for (op, a, x) in zip(ops, accs, inputs)]
        end
        push!(init_exprs, inits === nothing ? _FLoopInit() : Expr(:tuple, inits...))
        push!(all_rf_accs, accs)
        push!(all_rf_inputs, inputs)
        verify_unique_symbols(accs, "accumulator")
        verify_unique_symbols(inputs, "input")
        # TODO: input symbols just have to be unique within a
        # `@reduce` block.  This restriction (unique across all
        # `@reduce`) can be removed.
        initializers = [:($a = $x) for (a, x) in zip(accs, inputs)]
        function rf_body_with_init(pre_updates = [])
            quote
                $(pre_updates...)
                if $grouped_accs isa $_FLoopInit
                    $(initializers...)
                else
                    ($(accs...),) = $grouped_accs
                    $(updaters...)
                end
                $grouped_accs = ($(accs...),)
            end
        end
        combine_body = quote
            if $grouped_inputs isa $_FLoopInit
            else
                ($(inputs...),) = $grouped_inputs
                $(rf_body_with_init())
            end
        end
        push!(combine_bodies, combine_body)
        return rf_body_with_init(pre_updates)
    end

    body2, info = transform_loop_body(body1, accs_symbols)

    @gensym reducing_function combine_function result

    unpackers = map(enumerate(all_rf_accs)) do (i, accs)
        @gensym grouped_accs
        quote
            $grouped_accs = $result[$i]
            # Assign to accumulator only if it is updated at least once:
            if $grouped_accs isa $_FLoopInit
            else
                ($(accs...),) = $grouped_accs
            end
        end
    end
    unpack_state = Expr(:block, unpackers...)
    gotos = gotos_for(info.external_labels, unpack_state, result)
    mkdecl(x) = x |> Cat() |> Map(a -> :(local $a)) |> collect
    accs_declarations = mkdecl(all_rf_accs)
    inputs_declarations = mkdecl(all_rf_inputs)

    return quote
        $Base.@inline function $reducing_function(($(accs_symbols...),), $rf_arg)
            $(accs_declarations...)
            $body2
            return ($(accs_symbols...),)
        end
        $combine_function(_, b::$(Union{Goto,Return})) = b
        function $combine_function(($(accs_symbols...),), ($(inputs_symbols...),))
            $(accs_declarations...)
            $(inputs_declarations...)
            $(combine_bodies...)
            return ($(accs_symbols...),)
        end
        $_verify_no_boxes($reducing_function)
        $result = $_fold(
            $whencombine($combine_function, $reducing_function),
            $OnInit(() -> ($(init_exprs...),)),
            $coll,
            $maybe_set_simd($executor, $Val{$(simd)}()),
        )
        $result isa $Return && return $result.value
        $(gotos...)
        $unpack_state
        nothing
    end
end

struct _FLoopInit end

_fold(rf::RF, init, coll, exc::Executor) where {RF} =
    transduce(IdentityTransducer(), rf, init, coll, exc)

function Base.showerror(io::IO, opspecs::ReduceOpSpec)
    print(io, "`@reduce(")
    join(io, opspecs.args, ", ")
    print(io, ")` used outside `@floop`")
end
