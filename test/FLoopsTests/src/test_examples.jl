module TestExamples

using Test

examplesbase = joinpath(dirname(@__DIR__), "examples")
examples = []
for (root, _, files) in walkdir(examplesbase)
    for name in files
        endswith(name, ".jl") || continue
        relname = joinpath(relpath(root, examplesbase), name)
        push!(examples, relname => joinpath(root, name))
    end
end

const modules = Dict()

@testset "$relname" for (relname, fullpath) in examples
    modules[relname] = m = Module()
    @eval m using LiterateTest.AssertAsTest: @assert
    Base.include(m, fullpath)
end

end  # module
