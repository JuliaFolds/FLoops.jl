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

See the module docstring of [`Floops`](@ref) for examples.
"""
macro floop(ex)
    # TODO: support SIMD
    esc(floop(macroexpand(__module__, ex)))
end

struct Return{T}
    value::T
end

struct Goto{label,T}
    acc::T
end

Goto{label}(acc::T) where {label,T} = Goto{label,T}(acc)
gotoexpr(label::Symbol) = :($Goto{$(QuoteNode(label))})

function floop(ex)
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

    external_labels = setdiff(gotos_in(ex), labels_in(ex))
    init_vars = mapcat(assigned_vars, pre)
    foldlex = @match loops begin
        Expr(:block, loop_axes...) => begin
            loop_vars, coll = transform_multi_loop(loop_axes)
            rf_arg = :(($(reverse(loop_vars)...),))
            asfoldl(rf_arg, coll, body, init_vars, external_labels)
        end
        Expr(:(=), rf_arg, coll) => begin
            asfoldl(rf_arg, coll, body, init_vars, external_labels)
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

function asfoldl(rf_arg, coll, body, state_vars, external_labels)
    @gensym step acc xf foldable
    # state_vars = extract_state_vars(body)
    pack_state = :((; $([Expr(:kw, v, v) for v in state_vars]...)))
    unpack_state = [:($v = $acc.$v) for v in state_vars]
    state_declarations = [:(local $v) for v in state_vars]
    gotos = map(external_labels) do label
        quote
            if $acc isa $(gotoexpr(label))
                let $acc = $acc.acc
                    $(unpack_state...)
                end
                $Base.@goto $label
            end
        end
    end
    info = (
        state_vars = state_vars,
        pack_state = pack_state,
        external_labels = external_labels,
        nested_for = false,
    )
    quote
        @inline function $step($acc, $rf_arg)
            $(state_declarations...)
            $(unpack_state...)
            $(as_rf_body(body, info))
            return $pack_state
        end
        $xf, $foldable = $extract_transducer($coll)
        $acc = $foldl($step, $xf, $foldable; init = $pack_state)
        $acc isa $Return && return $acc.value
        $(gotos...)
        $(unpack_state...)
        nothing
    end
end
# For now, using (private interface) `extract_transducer` as done in:
# https://github.com/tkf/ThreadsX.jl/pull/106.  But this should be
# done automatically in Transducers.jl.

function as_rf_body(body, info)
    @match body begin
        # Stop recursing into function definition
        Expr(:function, _...) => body
        Expr(:(=), Expr(:call, _...), _) => body
        Expr(:(=), Expr(:where, _...), _) => body
        Expr(:do, _...) => body

        # Do not transform `break` in inside other `for` loops:
        Expr(:for, nloop, nbody) =>
            Expr(:for, nbody, as_rf_body(nbody, @set info.nested_for = true))

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
                :((; $(args...))) => begin
                    map(args) do x
                        @match x begin
                            Expr(:kw, k, v) => Expr(:kw, k, get(d, k, v))
                        end
                    end
                end
            end
            info = @set info.state_vars = setdiff(info.state_vars, frozen_vars)
            info = @set info.pack_state = :((; $(pack_state_args...)))
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

vars_in(x::Symbol) = x
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
function gotos_in(ex::Expr)
    @match ex begin
        Expr(:symbolicgoto, label) => [label]
        Expr(_, args...) => mapcat(gotos_in, args)
    end
end

labels_in(_) = Symbol[]
function labels_in(ex::Expr)
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
    loop_vars = Symbol[]
    loop_collections = []
    is_triangular = false
    for ex in loop_axes
        @match ex begin
            Expr(:(=), var, axis) => begin
                is_triangular |= !isempty(intersect(loop_vars, unbound_rhs(axis)))
                push!(loop_vars, var)
                push!(loop_collections, axis)
            end
        end
    end
    if is_triangular
        axis_constructors = Any[]
        for (i, axis) in enumerate(loop_collections)
            vars = loop_vars[1:i-1]
            push!(axis_constructors, :(($(vars...),) -> $axis))
        end
        return (loop_vars, :($TriangularIterator(($(axis_constructors...),))))
    else
        return (loop_vars, :($Iterators.product($(reverse(loop_collections)...))))
    end
end
