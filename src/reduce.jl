"""
    @reduce() do (acc₁ [= init₁]; x₁), ..., (accₙ [= initₙ]; xₙ)
        ...
    end
    @reduce(acc₁ ⊗₁= x₁, ..., accₙ ⊗ₙ= xₙ)
    @reduce(acc₁ .⊗₁= x₁, ..., accₙ .⊗ₙ= xₙ)
    @reduce(acc₁ = ⊗₁(init₁, x₁), ..., accₙ = ⊗ₙ(initₙ, xₙ))

Declare how accumulators are updated in the sequential basecase and
how the resulting accumulators from two basecases are combined.

The arguments `accᵢ` and `xᵢ` must be symbols except for `xᵢ` of the
last three forms in which an expression can be used at `xᵢ`.

In the first form,

```julia
function ((acc₁, acc₂, ..., accₙ), (x₁, x₂, ..., xₙ))
    ...  # body of the `do` block
    return (acc₁, acc₂, ..., accₙ)
end
```

should be an associative function.

In the last three forms, every binary operation `⊗ᵢ` should be an associative
function.

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
    visible::Vector{Symbol}
end

ReduceOpSpec(args::Vector{Any}) = ReduceOpSpec(args, Symbol[])

"""
    @init begin
        pv₁ = init₁
        ...
        pvₙ = initₙ
    end

Initialize private variables `pvᵢ` with initializer expression `initᵢ` for
each task. This can be used for mutating objects in a data race-free manner.
"""
macro init(ex)
    :(throw($(initspec(ex))))
end

struct InitSpec
    expr::Expr
    lhs::Vector{Union{Symbol,Expr}}
    rhs::Vector{Any}
    visible::Vector{Symbol}
end

InitSpec(expr::Expr, lhs::Vector{Union{Symbol,Expr}}, rhs::Vector{Any}) =
    InitSpec(expr, lhs, rhs, Symbol[])

initspec(@nospecialize x) = invalid_at_init(x)
initspec(ex::Expr) = InitSpec(ex, collect_assignments(ex)...)

invalid_at_init(@nospecialize ex) =
    error("`@init` requires an assignment or a sequence of assignments; got:\n", ex)

# TODO: merge with `assigned_vars`?
collect_assignments(ex) = collect_assignments!(Union{Symbol,Expr}[], [], ex)
collect_assignments!(_, _, @nospecialize(x)) = invalid_at_init(x)
collect_assignments!(lhs, rhs, ::LineNumberNode) = (lhs, rhs)
function collect_assignments!(lhs, rhs, ex::Expr)
    @match ex begin
        Expr(:(=), l::Union{Symbol,Expr}, r) => begin
            push!(lhs, l)
            push!(rhs, r)
        end
        Expr(:block, args...) => begin
            for a in args
                collect_assignments!(lhs, rhs, a)
            end
        end
        # TODO: should we support other things, like side effects, here?
        _ => invalid_at_init(ex)
    end
    return (lhs, rhs)
end

""" Recursively copy `expr::Expr` but not `ReduceOpSpec` or `InitSpec`. """
copyexpr(expr::Expr) = Expr(expr.head, (copyexpr(a) for a in expr.args)...)
copyexpr(@nospecialize x) = x

function analyze_loop_local_variables!(spec::Union{ReduceOpSpec,InitSpec}, scopes)
    @assert isempty(spec.visible)
    append!(spec.visible, (var.name for sc in scopes for var in sc.bounds))
    unique!(spec.visible)
    nothing
end
function analyze_loop_local_variables!(expr::Expr, scopes)
    @match expr begin
        Expr(:scoped, sc, inner) => begin
            push!(scopes, sc)
            analyze_loop_local_variables!(inner, scopes)
            pop!(scopes)
            nothing
        end
        _ => begin
            for a in expr.args
                analyze_loop_local_variables!(a, scopes)
            end
        end
    end
end
analyze_loop_local_variables!(@nospecialize(_), _) = nothing

""" Fill `visible` field of `ReduceOpSpec` and `InitSpec` in-place. """
function fill_loop_local_variables!(expr)
    ex = copyexpr(expr)  # deep copy expr but not ReduceOpSpec or InitSpec
    analyze_loop_local_variables!(solve_from_local!(simplify_ex(ex)), Any[])
    return expr
end
#
# Currently, we overestimate variables visible to `@reduce` and `@init`. For
# example, we treat that `a` is visible to `init` clause of `@reduce` (i.e.,
# `f(a)`) in the following example:
#
#     @reduce y = op(f(a), x)
#     a = 1
#
# This is for (relatively easily) supporting the uses of `let` like this:
#
#     julia> let
#                let
#                    a = 1
#                end
#                a
#            end
#     ERROR: UndefVarError: a not defined
#     ...
#
#     julia> let
#                let
#                    a = 1
#                end
#                @show a
#                a = 0
#                a
#            end
#     a = 1
#     1
#
# The latter is the example where the visibility of `a` at `@show a` is
# "retroactively" changed by the assignment after `@show a`; i.e., we cannot
# use simple single forward-pass algorithm to compute the set of accessible
# variables at given points.


function unpack_kwargs(;
    otherwise = donothing,
    on_expr = otherwise,
    on_init = otherwise,
    kwargs...,
)
    @assert isempty(kwargs)
    return (otherwise, on_expr, on_init)
end

function on_reduce_op_spec(on_spec, ex; kwargs...)
    (otherwise, on_expr, on_init) = unpack_kwargs(; kwargs...)
    @match ex begin
        Expr(:call, throw′, spec::ReduceOpSpec) => on_spec(spec)
        Expr(:call, throw′, spec::InitSpec) => on_init(spec)
        Expr(head, args...) => begin
            new_args = map(args) do x
                on_reduce_op_spec(on_spec, x; kwargs...)
            end
            on_expr(head, new_args...)
        end
        _ => otherwise(ex)
    end
end

on_reduce_op_spec_reconstructing(on_spec, ex; otherwise = identity, on_init = otherwise) =
    on_reduce_op_spec(on_spec, ex; on_expr = Expr, otherwise = otherwise, on_init = on_init)

is_parallel(ex) = on_reduce_op_spec(
    _ -> true,
    ex;
    on_init = _ -> true,
    on_expr = (_, args...) -> any(args),
    otherwise = _ -> false,
)

function floop_parallel(ctx::MacroContext, ex::Expr, simd, executor = nothing)
    if !isexpr(ex, :for, 2)
        error("expected a `for` loop; got:\n", ex)
    end
    iterspec, body = ex.args
    parallel_loop_ex = @match iterspec begin
        Expr(:block, loop_axes...) => begin
            rf_arg, coll = transform_multi_loop(loop_axes)
            as_parallel_loop(ctx, rf_arg, coll, body, simd, executor)
        end
        Expr(:(=), rf_arg, coll) => begin
            as_parallel_loop(ctx, rf_arg, coll, body, simd, executor)
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
        msg = string(
            "[NOT IMPLEMENTED]",
            " Currently, initial value should be specified for all accumulators",
            " when it is specified for at least one accumulator.",
        )
        throw(ArgumentError(msg))
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
            @gensym input
            push!(pre_updates, :($input = $x))
            push!(inputs, input)
        end
    end
    return (inputs, pre_updates)
end

function _lazydotcall end
struct LazyDotCall{T}
    value::T
end
@inline Broadcast.broadcasted(::typeof(_lazydotcall), x) = LazyDotCall(x)
@inline Broadcast.materialize(x::LazyDotCall) = x.value

function uniquify_inputs(inputs)
    uniquified = empty(inputs)
    pre_updates = Expr[]
    seen = Set{eltype(inputs)}()
    for x in inputs
        if x in seen
            y = gensym(x)
            push!(pre_updates, :($y = $x))
        else
            push!(seen, x)
            y = x
        end
        push!(uniquified, y)
    end
    return uniquified, pre_updates
end

function inject_spec_expr_for_analysis(ex::Expr)
    function on_init(spec::InitSpec)
        quote
            $(spec.expr)
            throw($spec)
        end
    end
    function on_reduce(spec::ReduceOpSpec)
        # If we want to make
        #     @reduce(a = op(a0, x))
        #     @reduce(b = op(f(a), x))
        # work, we need to do something here. But, for the moment, let us
        # pretend that the output of `@reduce` is not visible outside the
        # `@reduce` block.
        :(throw($spec))
    end
    return on_reduce_op_spec_reconstructing(on_reduce, ex; on_init = on_init)
end

raw"""
    process_reduce_op_spec(spec) ->
        (; inits, accs, inputs, pre_updates, initializers, updaters)

Process an invocation of `@reduce() do ...` or `@reduce(spec₁, spec₂, ...)`
where each `specᵢ` is one of the following form

    acc ⊗= input
    acc .⊗= input
    acc = ⊗(init, input)

Roughly speaking, the processed results are injected to the loop body as follows
(see `rf_body_with_init` for exactly how this happens):

```
local $(accs...)
for x in xs
    ...

    # <- where `@reduce` is invoked
    $(pre_updates...)       # assign $inputs
    if $THIS_IS_THE_FIRST_ITERATION
        $(initializers...)  # "per-task" lazy initialization occurs here
    else
        $(updaters...)      # the main update logic; e.g., `acc = acc + x`
    end
end
```

To combine `accs`, following expressions are injected to the `combine_function`:

```julia
function $combine_function(all_accs, all_inputs)
    (..., ($(accs...),), ...) = all_accs      # results from left
    (..., ($(inputs...),), ...) = all_inputs  # results from right
    ...  # code from other reductions

    if $RIGHT_IS_EMPTY
        # do nothing; i.e., use the left result as-is
    else
        # Note: no $(pre_updates...) here
        if $LEFT_IS_EMPTY
            $(initializers...)
        else
            $(updaters...)
        end
    end

    ...  # code from other reductions
    return (..., ($(accs...),), ...)  # combined results
end
```
"""
function process_reduce_op_spec(
    spec::ReduceOpSpec,
)::NamedTuple{(:inits, :accs, :inputs, :pre_updates, :initializers, :updaters)}
    opspecs = spec.args::Vector{Any}

    if length(opspecs) == 1 && is_function(opspecs[1])
        # handle: @reduce() do ...
        rf_ex, = opspecs
        # rf_ex = :(((acc1; input1), ..., (accN; inputN)) -> rf_body)
        accs, inits, inputs = analyze_rf_args(rf_ex.args[1])
        rf_body = rf_ex.args[2]
        pre_updates = []
        updaters = [rf_body]
        initializers = default_initializers(inits, accs, inputs, updaters)
        return (;
            inits = inits,
            accs = accs,
            inputs = inputs,
            pre_updates = pre_updates,
            initializers = initializers,
            updaters = updaters,
        )
    end

    initializers = nothing
    need_materialize = false
    if all(is_dot_update, opspecs)
        # handle: @reduce(acc₁ .op₁= x₁, ..., accₙ .opₙ= xₙ)
        need_materialize = true
        ops = [Symbol(String(x.head)[2:end-1]) for x in opspecs]
        accs = [x.args[1] for x in opspecs]
        inits = nothing

        allsymbol = true
        inputs = []
        pre_updates = []
        initializers = []
        for expr in opspecs
            a = expr.args[1]  # acc
            x = expr.args[2]  # input
            local input::Symbol
            if x isa Symbol
                input = x
                push!(initializers, :($a = $input))
            else
                allsymbol = false
                @gensym input
                if is_dotcall(x)  # acc .⊗= f.(args...)
                    rhs = :($_lazydotcall.($x))

                    # Since the arguments of the broadcasted object may be
                    # invalid in the next iteration (e.g., it contains a
                    # temporary buffer), we need to materialize `rhs` right away
                    # in the first iteration.
                    instantiate = GlobalRef(Broadcast, :instantiate)
                    push!(initializers, :($a = $copy($instantiate($input))))
                else
                    rhs = x
                    push!(initializers, :($a = $input))
                end
                push!(pre_updates, :($input = $rhs))
            end
            push!(inputs, input)
        end
    elseif all(is_rebinding_update, opspecs)
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
        (inputs, pre_updates) = extract_pre_updates([x.args[2].args[3] for x in opspecs])
    else
        error(join(vcat(["unsupported:"], opspecs), "\n"))
    end
    inputs, pre_updates2 = uniquify_inputs(inputs)
    append!(pre_updates, pre_updates2)
    if need_materialize
        updaters = map(ops, accs, inputs) do op, a, x
            materialize!! = GlobalRef(@__MODULE__, :materialize!!)
            instantiate = GlobalRef(Broadcast, :instantiate)
            broadcasted = GlobalRef(Broadcast, :broadcasted)
            :($a = $materialize!!($a, $instantiate($broadcasted($op, $a, $x))))
            # ^- mutate-or-widen version of `$a .= ($op).($a, $x)`
        end
    else
        updaters = [:($a = $op($a, $x)) for (op, a, x) in zip(ops, accs, inputs)]
    end
    if initializers === nothing
        initializers = default_initializers(inits, accs, inputs, updaters)
    end
    return (;
        inits = inits,
        accs = accs,
        inputs = inputs,
        pre_updates = pre_updates,
        initializers = initializers,
        updaters = updaters,
    )
end

function default_initializers(inits, accs, inputs, updaters)
    if inits === nothing
        initializers = [:($a = $x) for (a, x) in zip(accs, inputs)]
    else
        initializers = [:($a = $x) for (a, x) in zip(accs, inits)]
        append!(initializers, updaters)
    end
    return initializers
end

function as_parallel_loop(ctx::MacroContext, rf_arg, coll, body0::Expr, simd, executor)
    body0 = deepcopy(body0)  # To be mutated by `fill_loop_local_variables!`.
    dummy_loop_body = quote  # Dummy expression that simulates the loop body for JuliaVariables.
        $rf_arg = nothing
        $(inject_spec_expr_for_analysis(body0))
    end
    fill_loop_local_variables!(dummy_loop_body)

    accs_symbols = Symbol[]
    inputs_symbols = Symbol[]
    init_exprs = []
    combine_bodies = []
    is_init = Bool[]  # `is_init[i]` is true iff `i`th accumulator is due to `@init`
    all_rf_inits = []
    all_rf_accs = []
    all_rf_inputs = []

    function check_invariance()
        num_state_groups = length(accs_symbols)
        @assert length(inputs_symbols) == num_state_groups
        @assert length(init_exprs) == num_state_groups
        @assert length(is_init) == num_state_groups
        @assert length(all_rf_inits) == num_state_groups
        @assert length(all_rf_accs) == num_state_groups
        @assert length(all_rf_inputs) == num_state_groups
        @assert length(combine_bodies) == num_state_groups

        nums_grouped_states = map(length, all_rf_accs)
        function check_num_states(xs)
            for (x, n) in zip(xs, nums_grouped_states)
                x === nothing && continue
                @assert length(x) == n
            end
        end
        check_num_states(all_rf_inits)
        check_num_states(all_rf_inputs)
    end

    function on_init(spec::InitSpec)
        @gensym grouped_private_states
        push!(accs_symbols, grouped_private_states)
        push!(inputs_symbols, :_)

        accs = spec.lhs
        push!(is_init, true)
        push!(all_rf_inits, nothing)
        push!(all_rf_accs, accs)
        push!(all_rf_inputs, nothing)
        verify_unique_symbols(accs, "private")

        # The corresponding combine function is "keep left" (i.e., do nothing):
        push!(combine_bodies, nothing)

        @gensym init_allocator
        scratch = quote
            $(spec.expr)  # the expression from `@init $initializer`; sets `accs`
            $Base.@inline $init_allocator() = tuple($(spec.rhs...))
            $ScratchSpace($init_allocator, ($(accs...),))
        end

        if isempty(intersect(spec.visible, unbound_rhs(spec.expr)))
            # Hoisting out `@init`, since it is not accessing variables used
            # inside the loop body.
            push!(init_exprs, scratch)
            return quote
                # Just in case it is demoted to `EmptyScratchSpace`:
                $grouped_private_states = $allocate($grouped_private_states)
                ($(accs...),) = $grouped_private_states.value
            end
        else
            push!(init_exprs, _FLoopInit())
            return quote
                if $grouped_private_states isa $_FLoopInit
                    # `$scratch` sets `$accs`.
                    # Assigning to `grouped_private_states` for reusing it next time.
                    $grouped_private_states = $scratch
                else
                    # Just in case it is demoted to `EmptyScratchSpace`:
                    $grouped_private_states = $allocate($grouped_private_states)
                    # After the initialization, just carry it over to the next iteration:
                    ($(accs...),) = $grouped_private_states.value
                end
            end
        end
    end

    body1 = on_reduce_op_spec_reconstructing(body0; on_init = on_init) do spec
        spec = spec::ReduceOpSpec
        @gensym grouped_accs grouped_inputs
        push!(accs_symbols, grouped_accs)
        push!(inputs_symbols, grouped_inputs)
        (inits, accs, inputs, pre_updates, initializers, updaters) =
            process_reduce_op_spec(spec)
        push!(is_init, false)
        push!(all_rf_inits, inits)
        push!(all_rf_accs, accs)
        push!(all_rf_inputs, inputs)
        verify_unique_symbols(accs, "accumulator")
        verify_unique_symbols(inputs, "input")
        # TODO: input symbols just have to be unique within a
        # `@reduce` block.  This restriction (unique across all
        # `@reduce`) can be removed.
        use_oninit =
            inits !== nothing && let visible = spec.visible
                if !isempty(pre_updates)
                    # `pre_updates` defines symbols that may be defined in `inits`
                    visible = mapfoldl(push!, pre_updates; init = copy(visible)) do ex
                        @assert isexpr(ex, :(=), 2)
                        ex.args[1]::Symbol
                    end
                end
                !any(!isempty(intersect(visible, unbound_rhs(ex))) for ex in inits)
            end
        if use_oninit
            # Hoisting out `init` clauses, since it is not accessing variables
            # used inside the loop body.
            push!(init_exprs, :(tuple($(inits...))))
        else
            push!(init_exprs, _FLoopInit())
        end
        function rf_body_with_init(pre_updates = [])
            if use_oninit
                return quote
                    $(pre_updates...)
                    ($(accs...),) = $grouped_accs
                    $(updaters...)
                    $grouped_accs = ($(accs...),)
                end
            end
            quote
                $(pre_updates...)
                if $grouped_accs isa $_FLoopInit
                    # TODO: Check if it is OK to just do `$grouped_accs = $grouped_inputs`
                    # when inside `combine_body`
                    $(initializers...)
                else
                    ($(accs...),) = $grouped_accs
                    $(updaters...)
                end
                $grouped_accs = ($(accs...),)
            end
        end
        combine_body0 = quote
            ($(inputs...),) = $grouped_inputs
            $(rf_body_with_init())
        end
        combine_body = if use_oninit
            combine_body0
        else
            quote
                if $grouped_inputs isa $_FLoopInit
                else
                    $combine_body0
                end
            end
        end
        push!(combine_bodies, combine_body)
        return rf_body_with_init(pre_updates)
    end
    check_invariance()

    body2, info = transform_loop_body(body1, accs_symbols)

    @gensym oninit_function reducing_function combine_function result
    if ctx.module_ === Main
        # Ref: https://github.com/JuliaLang/julia/issues/39895
        oninit_function = Symbol(:__, oninit_function)
        reducing_function = Symbol(:__, reducing_function)
        combine_function = Symbol(:__, combine_function)
    end

    unpackers = map(
        enumerate(zip(is_init, all_rf_accs, all_rf_inits, init_exprs)),
    ) do (i, (nounpack, accs, inits, ex))
        @gensym grouped_accs
        if nounpack
            # This accumulator is from `@init`.
            nothing
        elseif inits === nothing || ex === _FLoopInit()
            quote
                $grouped_accs = $result[$i]
                # Assign to accumulator only if it is updated at least once:
                if $grouped_accs isa $_FLoopInit
                else
                    ($(accs...),) = $grouped_accs
                end
            end
        else
            quote
                $grouped_accs = $result[$i]
                ($(accs...),) = if $grouped_accs isa $_FLoopInit
                    $unreachable_floop()
                    # ($(inits...),)
                else
                    $grouped_accs
                end
            end
        end
    end
    unpack_state = Expr(:block, unpackers...)
    gotos = gotos_for(info.external_labels, unpack_state, result)
    mkdecl(x) = x |> NotA(Nothing) |> Cat() |> Map(a -> :(local $a)) |> collect
    accs_declarations = mkdecl(all_rf_accs)
    inputs_declarations = mkdecl(all_rf_inputs)

    return quote
        $Base.@inline function $oninit_function()
            $(accs_declarations...)
            return tuple($(init_exprs...))
        end
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
            $wheninit(
                $oninit_function,
                $whencombine($combine_function, $reducing_function),
            ),
            $coll,
            $executor,
            $(Val(simd)),
        )
        $result isa $Return && return $result.value
        $(gotos...)
        $unpack_state
        nothing
    end
end

struct _FLoopInit end

@noinline unreachable_floop() = error("unrechable reached (FLoops.jl bug)")

@inline _fold(rf::RF, coll, ::Nothing, simd) where {RF} =
    _fold(rf, coll, PreferParallel(), simd)
@inline _fold(rf::RF, coll, exc::Executor, simd) where {RF} = unreduced(
    transduce(IdentityTransducer(), rf, DefaultInit, coll, maybe_set_simd(exc, simd)),
)

function Base.showerror(io::IO, opspecs::ReduceOpSpec)
    print(io, "`@reduce(")
    join(io, opspecs.args, ", ")
    print(io, ")` used outside `@floop`")
end

function Base.showerror(io::IO, spec::InitSpec)
    ex = spec.expr
    print(io, "`@init", ex, "` used outside `@floop`")
end
