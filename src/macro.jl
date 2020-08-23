"""
    @floop begin
        s₁ = initialization of s₁
        s₂  # pre-initialized variable
        ...
        for x in xs, ...
            ...
        end
    end

`@floop begin ... end` expects a (possibly empty) series of
assignments or variable declaration (as in `s₂` above) followed by a
`for` loop.

When there is no induction variables, `begin ... end` can be omitted:

    @floop for x in xs, ...
        ...
    end

Use [`@reduce`](@ref) for parallel execution:

    @floop for x in xs, ...
        ...
        @reduce ...
    end

`@floop` with `@reduce` can take an `executor` argument (which should
be an instance of one of `SequentialEx`, `ThreadedEx` and
`DistributedEx`):

    @floop executor for x in xs, ...
        ...
        @reduce ...
    end

See the module docstring of [`Floops`](@ref) for examples.
"""
macro floop(ex)
    ex, simd = remove_at_simd(__module__, ex)
    exx = macroexpand(__module__, ex)
    has_reduce(exx) && return esc(floop_parallel(exx, simd))
    esc(floop(exx, simd))
end

macro floop(executor, ex)
    ex, simd = remove_at_simd(__module__, ex)
    exx = macroexpand(__module__, ex)
    esc(floop_parallel(exx, simd, executor))
end

struct Return{T}
    value::T
end

struct Goto{label,T}
    acc::T
end

Goto{label}(acc::T) where {label,T} = Goto{label,T}(acc)
gotoexpr(label::Symbol) = :($Goto{$(QuoteNode(label))})

function floop(ex, simd)
    pre = post = Union{}[]
    ansvar = :_
    if isexpr(ex, :for)
        loops, body = _for_loop(ex)
    elseif isexpr(ex, :block)
        args = flattenblockargs(ex)
        i, ansvar, loops, body =
            find_first_for_loop(args) |> ifnothing() do
                throw(ArgumentError("Unsupported expression:\n$ex"))
            end
        pre = args[1:i-1]
        post = args[i+1:end]
        if find_first_for_loop(post) !== nothing
            throw(ArgumentError("Multiple top-level `for` loop found in:\n$ex"))
        end
    else
        throw(ArgumentError("Unsupported expression:\n$ex"))
    end
    if ansvar !== :_
        post = vcat(post, ansvar)
    end

    init_vars = mapcat(assigned_vars, pre)
    foldlex = @match loops begin
        Expr(:block, loop_axes...) => begin
            rf_arg, coll = transform_multi_loop(loop_axes)
            asfoldl(rf_arg, coll, body, init_vars, simd)
        end
        Expr(:(=), rf_arg, coll) => begin
            asfoldl(rf_arg, coll, body, init_vars, simd)
        end
    end
    return Expr(:block, pre..., :($ansvar = $foldlex), post...)
end

function _for_loop(ex)
    if isexpr(ex, :for) && length(ex.args) == 2
        return ex.args
    end
    throw(ArgumentError("Malformed `for` block:\n$ex"))
end

find_first_for_loop(args) =
    firstsomething(enumerate(args)) do (i, x)
        @match x begin
            Expr(:for, loops, body) => return (i, :_, loops, body)
            Expr(:local, Expr(:(=), ansvar, Expr(:for, loops, body))) =>
                return (i, ansvar, loops, body)
            _ => nothing
        end
    end

function gotos_for(external_labels::Vector{Symbol}, unpack_state::Expr, acc::Symbol)
    gotos = map(external_labels) do label
        quote
            if $acc isa $(gotoexpr(label))
                let $acc = $acc.acc
                    $unpack_state
                end
                $Base.@goto $label
            end
        end
    end
    return gotos
end

function asfoldl(rf_arg, coll, body0, state_vars, simd)
    @assert simd in (false, true, :ivdep)
    body, info = transform_loop_body(body0, state_vars)
    @gensym step acc xf foldable
    pack_state = info.pack_state
    unpack_state = :(($(state_vars...),) = $acc)
    gotos = gotos_for(info.external_labels, unpack_state, acc)
    state_declarations = [:(local $v) for v in state_vars]
    quote
        @inline function $step($acc, $rf_arg)
            $(state_declarations...)
            $unpack_state
            $body
            return $pack_state
        end
        $xf, $foldable = $extract_transducer($coll)
        $acc = $foldl($step, $xf, $foldable; init = $pack_state, simd = $(Val(simd)))
        $acc isa $Return && return $acc.value
        $(gotos...)
        $unpack_state
        nothing
    end
end
# For now, using (private interface) `extract_transducer` as done in:
# https://github.com/tkf/ThreadsX.jl/pull/106.  But this should be
# done automatically in Transducers.jl.

function transform_loop_body(body, state_vars)
    external_labels::Vector{Symbol} = setdiff(gotos_in(body), labels_in(body))
    # state_vars = extract_state_vars(body)
    pack_state = :(($(state_vars...),))
    info = (
        state_vars = state_vars,
        pack_state = pack_state,
        external_labels = external_labels,
        nested_for = false,
    )
    return as_rf_body(body, info), info
end

function as_rf_body(body, info)
    is_function(body) && return body
    @match body begin
        # Do not transform `break` in inside other `for` loops:
        Expr(:for, nloop, nbody) =>
            Expr(:for, nloop, as_rf_body(nbody, @set info.nested_for = true))

        Expr(:continue) => info.nested_for ? body : :(return $(info.pack_state))
        Expr(:break) => info.nested_for ? body : :(return $reduced($(info.pack_state)))
        Expr(:return) => :(return $reduced($Return(nothing)))
        Expr(:return, value) => :(return $reduced($Return($value)))
        Expr(:symbolicgoto, label) => if label in info.external_labels
            :(return $reduced($(gotoexpr(label))($(info.pack_state))))
        else
            body
        end

        Expr(:let, let_bindings_, let_body) => begin
            let_bindings = @match let_bindings_ begin
                Expr(:block, args...) => collect(args)
                b => [b]
            end
            let_vars = map(let_bindings) do x
                @match x begin
                    _::Symbol => x
                    Expr(:(=), x, _) => x
                end
            end
            frozen_vars = intersect(info.state_vars, let_vars)
            gensym_vars = map(gensym, frozen_vars)
            d = Dict(zip(frozen_vars, gensym_vars))
            pack_state_args = @match info.pack_state begin
                :(($(args...),)) => begin
                    map(a -> get(d, a, a), args)
                end
            end
            info = @set info.state_vars = setdiff(info.state_vars, frozen_vars)
            info = @set info.pack_state = :(($(pack_state_args...),))
            all_bindings = map(gensym_vars, frozen_vars) do g, f
                :($g = $f)
            end
            append!(all_bindings, let_bindings)
            Expr(:let, Expr(:block, all_bindings...), as_rf_body(let_body, info))
        end

        Expr(head, args...) => Expr(head, [as_rf_body(a, info) for a in args]...)

        _ => body
    end
end

assigned_vars(x::Symbol) = [x]
assigned_vars(::Any) = Symbol[]
function assigned_vars(ex::Expr)
    @match ex begin
        Expr(:(=), lhs, rhs) => vcat(vars_in(lhs), assigned_vars(rhs))
        Expr(:tuple, lhs1..., Expr(:(=), lhs2, rhs)) =>
            vcat(mapfoldl(vars_in, vcat, lhs1), vars_in(lhs2), assigned_vars(rhs))
        # Is it better to be permissive here?
        _ => Symbol[]
    end
end

vars_in(x::Symbol) = [x]
function vars_in(ex)
    @match ex begin
        Expr(:tuple, vars...) => vars
        _ => Symbol[]
    end
end

# extract_state_vars(body) =
#     mutated_global_vars(solve!(simplify_ex(deepcopy(body))))

# function mutated_global_vars(ex)
#     return @match ex begin
#         Expr(:(=), lhs, rhs) => begin
#             if lhs isa Var && lhs.is_global
#                 append!([lhs.name], mutated_global_vars(rhs))
#             else
#                 mutated_global_vars(rhs)
#             end
#         end
#         Expr(_, args...) => mapreduce(mutated_global_vars, vcat, args)
#         _ => Union{}[]
#     end
# end

gotos_in(_) = Symbol[]
function gotos_in(ex::Expr)::Vector{Symbol}
    @match ex begin
        Expr(:symbolicgoto, label) => [label]
        Expr(_, args...) => mapcat(gotos_in, args)
    end
end

labels_in(_) = Symbol[]
function labels_in(ex::Expr)::Vector{Symbol}
    @match ex begin
        Expr(:symboliclabel, label) => [label]
        Expr(_, args...) => mapcat(labels_in, args)
    end
end

unbound_rhs(x::Symbol) = [x]
unbound_rhs(ex::Expr) = _global_rhs(solve!(simplify_ex(deepcopy(ex))))
_global_rhs(_) = Symbol[]
_global_rhs(x::Var) = x.is_global ? [x.name] : Symbol[]
function _global_rhs(ex::Expr)
    @match ex begin
        Expr(:(=), _, rhs) => _global_rhs(rhs)
        Expr(:tuple, _..., Expr(:(=), _, rhs)) => _global_rhs(rhs)
        Expr(_, args...) => mapreduce(_global_rhs, vcat, args)
    end
end

function transform_multi_loop(loop_axes)
    all_loop_vars = Symbol[]
    loop_vars = []
    loop_collections = []
    is_triangular = false
    for ex in loop_axes
        @match ex begin
            Expr(:(=), var, axis) => begin
                is_triangular |= !isempty(intersect(all_loop_vars, unbound_rhs(axis)))
                append!(all_loop_vars, vars_in(var))
                push!(loop_vars, var)
                push!(loop_collections, axis)
            end
        end
    end
    rf_arg = :(($(reverse(loop_vars)...),))
    if is_triangular
        coll = foldr(
            collect(zip(loop_vars, loop_collections));  # `collect` for Julia 1.0
            init = :($(reverse(loop_vars)...),),
        ) do (v, axis), coll
            f = gensym("loop_axis_$v")
            Expr(:call, |>, axis, quote
                $f($v) = $coll  # should it be inlined?
                $Map($f)
            end)
        end
        for _ in 2:length(loop_collections)
            coll = Expr(:call, |>, coll, :($Cat()))
        end
        return (rf_arg, coll)
    else
        return (rf_arg, :($Iterators.product($(reverse(loop_collections)...))))
    end
end
#
# Notes on triangular loops: For example, a `for` loop specification
# `for x in xs, y in f(x), z in g(x, y)` is transformed to
#
#     xs |> Map() do x
#         f(x) |> Map() do y
#             g(x, y) |> Map() do z
#                 (z, y, x)
#             end
#         end
#     end |> Cat() |> Cat()
#
# `Cat`s are composed outside so that `foldxt` can (in principle)
# rewrite the transducer to use `TCat` to parallelize inner loops.

function resolvesymbol(m, e)
    @match e begin
        Expr(:., a, QuoteNode(b::Symbol)) => begin
            x = resolvesymbol(m, a)
            x isa Module ? getfield(x, b) : nothing
        end
        (a::Symbol) => getfield(m, a)
        _ => nothing
    end
end

"""
    remove_at_simd(__module__, ex) -> (ex′, simd)

Return a tuple with following items:

* `ex′`: `ex` without the first top-level macrocall to `Base.@simd` removed.
* `simd`: `true` if `@simd for ... end` is found. `:ivdep` if `@simd
  ivdep for ... end` is found.  `false` otherwise.

Macros that happened to have the name `@simd` but not identical to
`Base.@simd` are ignored.
"""
function remove_at_simd(__module__, ex)
    ans = @match ex begin
        Expr(:macrocall, mcr, ::LineNumberNode, options..., loop) => begin
            if (
                isexpr(loop, :for) &&
                resolvesymbol(__module__, mcr) === getfield(Base, Symbol("@simd"))
            )
                if options == [:ivdep]
                    return loop, :ivdep
                elseif options == []
                    return loop, true
                end
            end
        end
        Expr(:block, args...) => begin
            for (i, x) in enumerate(args)
                y, simd = remove_at_simd(__module__, x)
                if simd !== false
                    return Expr(:block, args[1:i-1]..., y, args[i+1:end]...), simd
                end
            end
        end
        _ => nothing
    end
    ans === nothing || return ans
    return ex, false
end
