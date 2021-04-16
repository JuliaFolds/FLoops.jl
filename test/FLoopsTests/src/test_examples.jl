module TestExamples

using Test

examplesbase = joinpath(dirname(dirname(dirname(@__DIR__))), "examples")
examples = []
for (root, _, files) in walkdir(examplesbase)
    for name in files
        endswith(name, ".jl") || continue
        relname = joinpath(relpath(root, examplesbase), name)
        push!(examples, relname => joinpath(root, name))
    end
end

const modules = Dict()

function test(relname, fullpath)
    modules[relname] = m = Module()
    @eval m using LiterateTest.AssertAsTest: @assert
    Base.include(m, fullpath)
end

function test()
    @testset "$relname" for (relname, fullpath) in examples
        test(relname, fullpath)
    end
end

end  # module
