module TestAstTools

using FLoops: unbound_rhs, is_dotcall
using Test

function test_unbound_rhs()
    @test unbound_rhs(:a) == [:a]
    @test unbound_rhs(:(
        let x = 1
            (x, y)
        end
    )) == [:y]
    @test unbound_rhs(quote end) == []
    @test unbound_rhs(quote
        ()
    end) == []
    @test unbound_rhs(quote
        []
    end) == []
    @test unbound_rhs(nothing) == []
end

function test_is_dotcall()
    @test is_dotcall(:(a .+ b))
    @test is_dotcall(:(.√a))
    @test is_dotcall(:(f.(x)))
    @test is_dotcall(:((f.a).(b)))
    @test !is_dotcall(:(a + b))
    @test !is_dotcall(:(√a))
    @test !is_dotcall(:(f(x)))
    @test !is_dotcall(:(f.a))
    @test !is_dotcall(:((f.a)(b)))
    @test !is_dotcall(:(f.a(b)))
end

end  # module
