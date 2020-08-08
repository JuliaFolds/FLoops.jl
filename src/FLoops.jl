module FLoops

# Use README as the docstring of the module:
@doc let path = joinpath(dirname(@__DIR__), "README.md")
    include_dependency(path)
    replace(read(path, String), r"^```julia"m => "```jldoctest README")
end FLoops

export @floop, @reduce, DistributedEx, SequentialEx, ThreadedEx

using Base.Meta: isexpr
using JuliaVariables: JuliaVariables, Var, simplify_ex
using MLStyle: @match
using Setfield: @set
using Transducers:
    @return_if_reduced,
    Cat,
    Map,
    MapCat,
    OnInit,
    ReduceIf,
    Reduction,
    Transducers,
    complete,
    extract_transducer,
    foldl_nocomplete,
    foldxd,
    foldxl,
    foldxt,
    next,
    reduced,
    right,
    whencombine

if isdefined(JuliaVariables, :solve!)
    using JuliaVariables: solve!
else
    const solve! = JuliaVariables.solve
end

if !@isdefined isnothing
    using Compat: isnothing
end

include("utils.jl")
include("macro.jl")
include("reduce.jl")
include("checkboxes.jl")

end # module
