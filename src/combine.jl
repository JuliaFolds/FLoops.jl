"""
    @combine left ⊗= _
    @combine left = _ ⊗ _
    @combine left = op(_ , _)
    @combine left .⊗= _
    @combine left .= _ .⊗ _
    @combine left .= op.(_, _)
    @combine() do (left₁; right₁), ..., (leftₙ; rightₙ)
        ...
    end

Declare how accumulators from two basecases are combined.  Unlike `@reduce`, the
reduction for the basecase is not defined by this macro.
"""
macro combine(ex)
    :(throw($(CombineOpSpec(Any[ex]))))
end

macro combine(ex1, ex2, exprs...)
    error("""
    Unlike `@reduce`, `@combine` only supports single expression.
    Use:
        @combine a += _
        @combine b += _
    Instead of:
        @combine(a += _, b += _)
    """)
end

struct CombineOpSpec <: OpSpec
    args::Vector{Any}
    visible::Vector{Symbol}
end

CombineOpSpec(args::Vector{Any}) = CombineOpSpec(args, Symbol[])

function combine_parallel_loop(ctx::MacroContext, ex::Expr, simd, executor = nothing)
    iterspec, body, ansvar, pre, post = destructure_loop_pre_post(ex)
    @assert ansvar == :_

    parallel_loop_ex = @match iterspec begin
        Expr(:block, loop_axes...) => begin
            rf_arg, coll = transform_multi_loop(loop_axes)
            as_parallel_combine_loop(ctx, pre, post, rf_arg, coll, body, simd, executor)
        end
        Expr(:(=), rf_arg, coll) => begin
            as_parallel_combine_loop(ctx, pre, post, rf_arg, coll, body, simd, executor)
        end
    end
    return parallel_loop_ex
end

function extract_spec(ex)
    @match ex begin
        Expr(:call, throw′, spec::ReduceOpSpec) => spec
        Expr(:call, throw′, spec::CombineOpSpec) => spec
        Expr(:call, throw′, spec::InitSpec) => spec
        _ => nothing
    end
end

function as_parallel_combine_loop(
    ctx::MacroContext,
    pre::Vector,
    post::Vector,
    rf_arg,
    coll,
    body0::Expr,
    simd,
    executor,
)
    @assert simd in (false, true, :ivdep)

    init_exprs = []
    all_rf_accs = []

    for ex in pre
        ex isa LineNumberNode && continue
        spec = extract_spec(ex)
        spec isa InitSpec || error("non-`@init` expression before `for` loop: ", ex)

        accs = spec.lhs
        push!(all_rf_accs, accs)

        # The expression from `@init $initializer`; sets `accs`:
        push!(init_exprs, spec.expr)
    end
    # Accumulator for the basecase reduction; i.e., the first argument to the
    # `next` reducing step function:
    base_accs = mapcat(identity, all_rf_accs)

    firstcombine = something(
        findfirst(x -> extract_spec(x) isa CombineOpSpec, post),
        lastindex(post) + 1,
    )
    completebasecase_exprs = post[firstindex(post):firstcombine-1]

    left_accs = []
    right_accs = []
    combine_bodies = []
    for i in firstcombine:lastindex(post)
        ex = post[i]
        ex isa LineNumberNode && continue
        spec = extract_spec(ex)
        if !(spec isa CombineOpSpec)
            error(
                "non-`@combine` expressions must be placed between `for` loop and the first `@combine` expression: ",
                spec,
            )
        end
        left, right, combine_body = process_combine_op_spec(spec)
        append!(left_accs, left)
        append!(right_accs, right)
        push!(combine_bodies, combine_body)
    end

    # TODO: handle `@reduce` in  the loop body
    @gensym result
    # See also: `asfoldl`:
    body, info = transform_loop_body(body0, base_accs)
    pack_state = info.pack_state
    unpack_state = :(($(left_accs...),) = $result)
    gotos = gotos_for(info.external_labels, unpack_state, result)
    base_accs_declarations = [:(local $v) for v in base_accs]
    left_accs_declarations = [:(local $v) for v in left_accs]
    right_accs_declarations = [:(local $v) for v in right_accs]

    @gensym(
        oninit_function,
        reducing_function,
        completebasecase_function,
        combine_function,
        context_function,
    )
    return quote
        $Base.@inline function $oninit_function()
            $(base_accs_declarations...)
            return tuple($(init_exprs...))
        end
        $Base.@inline function $reducing_function(($(base_accs...),), $rf_arg)
            $(base_accs_declarations...)
            $body
            return ($(base_accs...),)
        end
        function $completebasecase_function(($(base_accs...),))
            $(base_accs_declarations...)
            $(left_accs_declarations...)
            $(completebasecase_exprs...)
            return ($(left_accs...),)
        end
        $combine_function(_, b::$(Union{Goto,Return})) = b
        function $combine_function(($(left_accs...),), ($(right_accs...),))
            $(left_accs_declarations...)
            $(right_accs_declarations...)
            $(combine_bodies...)
            return ($(left_accs...),)
        end
        $context_function() = (; ctx = $ctx, id = $(QuoteNode(gensym(:floop_id))))
        $_verify_no_boxes($reducing_function, $context_function)
        $result = $_fold(
            $wheninit(
                $oninit_function,
                $whencompletebasecase(
                    $completebasecase_function,
                    $whencombine($combine_function, $reducing_function),
                ),
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

function process_combine_op_spec(
    spec::CombineOpSpec,
)::NamedTuple{(:left, :right, :combine_body)}
    @assert length(spec.args) == 1
    ex, = spec.args::Vector{Any}

    if is_function(ex)
        # handle: @combine() do ...
        rf_ex = ex
        # rf_ex = :(((left1; right1), ..., (leftN; rightN)) -> rf_body)
        left, inits, right = analyze_rf_args(rf_ex.args[1])
        if inits !== nothing
            error("`@combine() do` syntax does not support initalization; got:\n", spec)
        end
        combine_body = rf_ex.args[2]
        return (; left = left, right = right, combine_body = combine_body)
    end

    if is_dot_update(ex)
        # handle: @combine left .⊗= _
        op = Symbol(String(ex.head)[2:end-1])
        lhs = ex.args[1]
        if ex.args[2] !== :_
            error(
                "expected expression of form `@combine lhs .⊗= _`; the rhs is not `_`: ",
                ex,
            )
        end
        true
    elseif isexpr(ex, :(.=), 2)
        if !is_dotcall(ex.args[2], 2)
            error(
                "`@combine lhs .= rhs` syntax requires a binary dot call",
                " (e.g., `a .+ b` or `f.(a, b)`) on the rhs; got:\n",
                ex,
            )
        end
        # handle: @combine left .= op.(_, _)
        lhs, rhs = ex.args
        if isexpr(rhs, :call, 3)
            dotop, l, r = rhs.args
            str = String(dotop)
            @assert startswith(str, ".")
            op = Symbol(str[2:end])
        else
            @assert rhs.head == :. &&
                    length(rhs.args) == 2 &&
                    isexpr(rhs.args[2], :tuple, 2)
            op = rhs.args[1]
            l, r = rhs.args[2].args
        end
        if !(l === r === :_)
            error(
                "`@combine lhs .= rhs` syntax expects that the arguments",
                " of the rhs are `_`; got: ",
                ex,
            )
        end
        true
    else
        false
    end && begin
        left = Any[lhs]
        rightarg = lhs isa Symbol ? gensym(Symbol(lhs, :_right)) : gensym(:right)
        right = Any[rightarg]
        broadcast_inplace!! = GlobalRef(@__MODULE__, :broadcast_inplace!!)
        combine_body = :($lhs = $broadcast_inplace!!($op, $lhs, $rightarg))
        #                ^- mutate-or-widen version of `$lhs .= ($op).($lhs, _)`
        # TODO: use accurate line number from `@combine`
        return (; left = left, right = right, combine_body = combine_body)
    end

    if is_rebinding_update(ex)
        # handle: @combine left ⊗= _
        op = Symbol(String(ex.head)[1:end-1])
        lhs, rhs = ex.args
        if rhs !== :_
            error(
                "expected expression of form `@combine lhs ⊗= _`; the rhs is not `_`: ",
                ex,
            )
        end
    elseif isexpr(ex, :(=), 2) && isexpr(ex.args[2], :call, 3)
        # handle: @combine left = op(_, _)
        lhs, rhs = ex.args
        op, l, r = rhs.args
        if !(l === r === :_)
            error(
                "`@combine lhs = rhs` syntax expects that the arguments",
                " of the rhs are `_`; got: ",
                ex,
            )
        end
    else
        error("unsupported: ", spec)
    end
    left = Any[lhs]
    rightarg = lhs isa Symbol ? gensym(Symbol(lhs, :_right)) : gensym(:right)
    right = Any[rightarg]
    combine_body = :($lhs = $op($lhs, $rightarg))
    # TODO: use accurate line number from `@combine`
    return (; left = left, right = right, combine_body = combine_body)
end
