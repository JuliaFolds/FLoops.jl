module TestSIMD

using FLoops
using Test

@testset "@simd" begin
    xs = 1:10
    @floop begin
        s = 0
        @simd for x in xs
            s += x
        end
    end
    @test s == sum(1:10)
end

@testset "@simd ivdep" begin
    xs = 1:10
    ys = similar(xs)
    @floop begin
        @simd ivdep for (i, x) in enumerate(xs)
            @inbounds ys[i] = 2x
        end
    end
    @test ys == 2 .* xs
end

@testset "Base.@simd" begin
    xs = 1:10
    @floop begin
        s = 0
        Base.@simd for x in xs
            s += x
        end
    end
    @test s == sum(1:10)
end

@testset "Base.@simd ivdep" begin
    xs = 1:10
    ys = similar(xs)
    @floop begin
        Base.@simd ivdep for (i, x) in enumerate(xs)
            @inbounds ys[i] = 2x
        end
    end
    @test ys == 2 .* xs
end

module TestFakeSIMD

using FLoops
using Test

macro simd(args...)
    esc(args[end])
end

@testset "@simd (not Base.@simd)" begin
    xs = 1:10
    @floop begin
        s = 0
        @simd for x in xs
            s += x
        end
    end
    @test s == sum(1:10)
end

@testset "@simd ivdep (not Base.@simd)" begin
    xs = 1:10
    ys = similar(xs)
    @floop begin
        @simd ivdep for (i, x) in enumerate(xs)
            @inbounds ys[i] = 2x
        end
    end
    @test ys == 2 .* xs
end

end  # module TestFakeSIMD

@testset "TestFakeSIMD.@simd" begin
    xs = 1:10
    @floop begin
        s = 0
        TestFakeSIMD.@simd for x in xs
            s += x
        end
    end
    @test s == sum(1:10)
end

@testset "TestFakeSIMD.@simd ivdep" begin
    xs = 1:10
    ys = similar(xs)
    @floop begin
        Base.@simd ivdep for (i, x) in enumerate(xs)
            @inbounds ys[i] = 2x
        end
    end
    @test ys == 2 .* xs
end

end  # module
