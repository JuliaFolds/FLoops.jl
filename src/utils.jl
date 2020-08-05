mapcat(f, xs) = collect(MapCat(f), xs)
firstsomething(f, xs) = foldl(right, xs |> Map(f) |> ReduceIf(!isnothing); init = nothing)
ifnothing(f) = x -> x === nothing ? f() : x
donothing(_...) = nothing

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

function is_rebinding_update_op(sym::Symbol)
    s = String(sym)
    endswith(s, "=") || return false
    op = Symbol(s[1:end-1])
    Base.isbinaryoperator(op) || return false
    return !isdefined(Base, sym)  # handle `<=` etc.
end
