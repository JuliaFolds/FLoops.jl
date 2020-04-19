module FLoops

export @floop

using Base.Meta: isexpr
using JuliaVariables: JuliaVariables, Var, simplify_ex
using MLStyle: @match
using Setfield: @set
using Transducers:
    @return_if_reduced,
    Map,
    MapCat,
    ReduceIf,
    Reduction,
    Transducers,
    complete,
    extract_transducer,
    foldl_nocomplete,
    next,
    reduced,
    right

if isdefined(JuliaVariables, :solve!)
    using JuliaVariables: solve!
else
    const solve! = JuliaVariables.solve
end

include("utils.jl")
include("triangular.jl")
include("macro.jl")

end # module
