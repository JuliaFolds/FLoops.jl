module TestAstTools

using FLoops: unbound_rhs
using Test

@testset "unbound_rhs" begin
    @test unbound_rhs(:a) == [:a]
    @test unbound_rhs(:(let x = 1; (x, y); end)) == [:y]
    @test unbound_rhs(quote end) == []
    @test unbound_rhs(quote () end) == []
    @test unbound_rhs(quote [] end) == []
    @test unbound_rhs(nothing) == []
end

end  # module
