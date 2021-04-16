module TestSIMD

using FLoops
using Test

function test_at_simd()
    xs = 1:10
    @floop begin
        s = 0
        @simd for x in xs
            s += x
        end
    end
    @test s == sum(1:10)
end

function test_at_simd_ivdep()
    xs = 1:10
    ys = similar(xs)
    @floop begin
        @simd ivdep for (i, x) in enumerate(xs)
            @inbounds ys[i] = 2x
        end
    end
    @test ys == 2 .* xs
end

function test_Base_at_simd()
    xs = 1:10
    @floop begin
        s = 0
        Base.@simd for x in xs
            s += x
        end
    end
    @test s == sum(1:10)
end

function test_Base_at_simd_ivdep()
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

function test_fake_at_simd()
    xs = 1:10
    @floop begin
        s = 0
        @simd for x in xs
            s += x
        end
    end
    @test s == sum(1:10)
end

function test_fake_at_simd_ivdep()
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

function test_TestFakeSIMD_at_simd()
    xs = 1:10
    @floop begin
        s = 0
        TestFakeSIMD.@simd for x in xs
            s += x
        end
    end
    @test s == sum(1:10)
end

function test_TestFakeSIMD_at_simd_ivdep()
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
