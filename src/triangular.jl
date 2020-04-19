struct TriangularIterator{C<:Tuple,A<:Tuple}
    constructors::C  # tuple of callables
    args::A  # items from collections of outer loop
end

TriangularIterator(constructors) = TriangularIterator(constructors, ())

@inline function Transducers.__foldl__(rf::RF, acc, itr::TriangularIterator) where {RF}
    acc = @return_if_reduced _foldl_ti(rf, acc, itr.args, itr.constructors...)
    return complete(rf, acc)
end

@inline function _foldl_ti(rf, acc, args, c, cs...)
    @inline f(x) = TriangularIterator(cs, (args..., x))
    return foldl_nocomplete(Reduction(MapCat(f), rf), acc, c(args...))
end

@inline _foldl_ti(rf, acc, args) = next(rf, acc, reverse(args))
