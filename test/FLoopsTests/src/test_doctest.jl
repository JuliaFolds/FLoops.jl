module TestDoctest
using PerformanceTestTools
function test()
    PerformanceTestTools.@include_foreach("__test_doctest.jl", [[]])
end
end  # module
