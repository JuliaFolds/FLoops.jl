module TestDoctest

using Documenter: doctest
using FLoops
using Test

function test()
    # Workaround `UndefVarError: FLoops not defined`
    @eval Main import FLoops
    doctest(FLoops, manual = true)
end

end  # module
