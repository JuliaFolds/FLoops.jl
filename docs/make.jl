using Documenter
using FLoops
using Literate
using LiterateTest
using LoadAllPackages

LoadAllPackages.loadall(joinpath((@__DIR__), "Project.toml"))

PAGES = [
    "index.md",
    "Tutorials" => [
        "Sequential loops" => "tutorials/sequential.md",
        "Parallel loops" => "tutorials/parallel.md",
    ],
    "How-to guides" => [
        # TODO: Finer grained pages?
        "How to do _X_ in parallel?" => "howto/parallel.md",
    ],
    "Reference" => [
        "API" => "reference/api.md",
        "Syntax" => "reference/syntax.md",
        # "Sequential loop" => "reference/sequential.md",
        "Parallelizable reduction (WIP)" => "reference/reduction.md",
    ],
    # "Explanation" => ...,
]

let example_dir = joinpath(dirname(@__DIR__), "examples")
    examples = Pair{String,String}[]

    for subpages in PAGES
        subpages isa Pair || continue
        for (_, mdpath) in subpages[2]::Vector
            stem, _ = splitext(mdpath)
            jlpath = joinpath(example_dir, "$stem.jl")
            if !isfile(jlpath)
                @info "`$jlpath` does not exist. Skipping..."
                continue
            end
            push!(examples, jlpath => joinpath(@__DIR__, "src", dirname(mdpath)))
        end
    end

    @info "Compiling example files" examples
    for (jlpath, dest) in examples
        Literate.markdown(jlpath, dest; config = LiterateTest.config(), documenter = true)
    end
end

makedocs(;
    sitename = "FLoops",
    format = Documenter.HTML(),
    modules = [FLoops],
    pages = PAGES,
)

deploydocs(; repo = "github.com/JuliaFolds/FLoops.jl", push_preview = true)
