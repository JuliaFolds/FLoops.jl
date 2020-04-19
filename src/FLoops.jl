module FLoops

export @floop

using JuliaVariables: JuliaVariables, Var, simplify_ex
using MLStyle: @match
using Setfield: @set
using Transducers:
    @return_if_reduced,
    MapCat,
    Reduction,
    Transducers,
    complete,
    extract_transducer,
    foldl_nocomplete,
    next,
    reduced

if isdefined(JuliaVariables, :solve!)
    using JuliaVariables: solve!
else
    const solve! = JuliaVariables.solve
end

include("triangular.jl")
include("macro.jl")

end # module
