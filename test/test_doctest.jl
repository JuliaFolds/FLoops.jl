module TestDoctest

using Documenter: doctest
using FLoops
using Test

@testset "doctest" begin
    doctest(FLoops, manual = false)
end

end  # module
