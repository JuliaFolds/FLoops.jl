module TestScratchSpace

using FLoops: Cleared, ScratchSpace, allocate
using Serialization
using Test

function roundtrip(x)
    @nospecialize
    buf = IOBuffer()
    serialize(buf, x)
    seek(buf, 0)
    return deserialize(buf)
end

function check_invariance(x)
    @nospecialize
    @assert !(x.value isa Cleared)
    @testset "allocate" begin
        @test allocate(x) === x
    end
    @testset "serialize: y = roundtrip(x)" begin
        y = roundtrip(x)
        @test y isa typeof(x)
        @test y.f === x.f
        @test y.value === Cleared()
        @testset "re-allocate: z = allocate(y)" begin
            z = allocate(y)
            @test z isa typeof(x)
            @test z.f === x.f
            @test z.value isa typeof(x.value)
        end
    end
    @testset "s = Some(x); t = roundtrip(s)" begin
        s = Some(x)
        t = roundtrip(s)
        @test typeof(t) === typeof(s)
        @test something(t).f === x.f
        @test something(t).value === Cleared()
    end
    @testset "y = roundtrip((x,))[1]" begin
        y = roundtrip((x,))[1]
        @test y isa typeof(x)
        @test y.f === x.f
        @test y.value === Cleared()
    end
end

makevector() = [123]
makeint() = 123

function test_invariance_mutable()
    @testset "x = ScratchSpace(makevector, makevector())" begin
        x = ScratchSpace(makevector, makevector())
        check_invariance(x)
    end
end

function test_invariance_immutable()
    @testset "x = ScratchSpace(makeint, makeint())" begin
        x = ScratchSpace(makeint, makeint())
        check_invariance(x)
    end
end

end  # module
