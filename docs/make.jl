using Documenter
using FLoops

makedocs(
    sitename = "FLoops",
    format = Documenter.HTML(),
    modules = [FLoops]
)

deploydocs(;
    repo = "github.com/JuliaFolds/FLoops.jl",
    push_preview = true,
)
