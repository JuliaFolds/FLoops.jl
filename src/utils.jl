mapcat(f, xs) = collect(MapCat(f), xs)
firstsomething(f, xs) = foldl(right, Map(f) |> ReduceIf(!isnothing), xs; init = nothing)
ifnothing(f) = x -> x === nothing ? f() : x

function flattenblockargs(ex)
    @match ex begin
        Expr(:block, args...) => mapcat(flattenblockargs, args)
        _ => [ex]
    end
end
