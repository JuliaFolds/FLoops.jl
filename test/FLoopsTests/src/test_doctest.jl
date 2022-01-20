module TestDoctest

using PerformanceTestTools
using Test

function test(; skip = true)
    if skip
        if lowercase(get(ENV, "JULIA_PKGEVAL", "false")) == "true"
            @info "Skipping doctests on PkgEval."
            @test_skip nothing
            return
        elseif VERSION < v"1.6"
            @info "Skipping doctests on Julia $VERSION."
            @test_skip nothing
            return
        end
    end
    PerformanceTestTools.@include_foreach("__test_doctest.jl", [[]])
end

end  # module
