struct MacroContext
    source::LineNumberNode
    module_::Module
end


mapcat(f, xs) = collect(MapCat(f), xs)
firstsomething(f, xs) = foldl(right, xs |> Map(f) |> ReduceIf(!isnothing); init = nothing)
ifnothing(f) = x -> x === nothing ? f() : x
donothing(_...) = nothing

@inline _any() = false
@inline _any(x) = x
@inline _any(x, xs...) = x || _any(xs...)
@inline _any(a, b) = a || b
@inline _any(a, b, c) = a || b || c
@inline _any(a, b, c, d) = a || b || c || d
@inline _any(a, b, c, d, e) = a || b || c || d || e
@inline _any(a, b, c, d, e, f) = a || b || c || d || e || f
@inline _any(a, b, c, d, e, f, g) = a || b || c || d || e || f || g
@inline _any(a, b, c, d, e, f, g, h) = a || b || c || d || e || f || g || h
@inline _any(a, b, c, d, e, f, g, h, i) = a || b || c || d || e || f || g || h || i
@inline _any(a, b, c, d, e, f, g, h, i, j) = a || b || c || d || e || f || g || h || i || j

function flattenblockargs(ex)
    @match ex begin
        Expr(:block, args...) => mapcat(flattenblockargs, args)
        _ => [ex]
    end
end


function is_function(ex)
    @match ex begin
        Expr(:function, _...) => true
        Expr(:(=), Expr(:call, _...), _) => true
        Expr(:(=), Expr(:where, _...), _) => true
        Expr(:do, _...) => true
        Expr(:->, _...) => true
        _ => false
    end
end


is_rebinding_update(ex) =
    ex isa Expr && length(ex.args) == 2 && is_rebinding_update_op(ex.head)

is_dot_update(ex) = ex isa Expr && length(ex.args) == 2 && is_dot_update_op(ex.head)

function is_rebinding_update_op(sym::Symbol)
    s = String(sym)
    endswith(s, "=") || return false
    op = Symbol(s[1:end-1])
    Base.isbinaryoperator(op) || return false
    return !isdefined(Base, sym)  # handle `<=` etc.
end

function is_dot_update_op(sym::Symbol)
    s = String(sym)
    startswith(s, ".") && endswith(s, "=") || return false
    op = Symbol(s[2:end-1])
    return Base.isbinaryoperator(op)
end

is_dot_op(_) = false
function is_dot_op(sym::Symbol)
    s = String(sym)
    startswith(s, ".") || return false
    op = Symbol(s[2:end])
    return Base.isoperator(op)
end

is_dotcall(ex) =
    if isexpr(ex, :call)
        length(ex.args) > 1 && is_dot_op(ex.args[1])
    else
        isexpr(ex, :., 2) && isexpr(ex.args[2], :tuple)
    end
