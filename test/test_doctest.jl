module TestDoctest

using Documenter: doctest
using FLoops
using Test

# Workaround `UndefVarError: FLoops not defined`
@eval Main import FLoops

@testset "doctest" begin
    doctest(FLoops, manual = true)
end

end  # module
