module TestCombine

using FLoops
using MicroCollections
using StaticArrays
using Test

function countmap_two_pass(indices, ex = nothing)
    l, h = extrema(indices)
    n = h - l + 1
    @floop ex for i in indices
        @init b = zeros(Int, n)
        b[i-l+1] += 1
        @combine h .+= b
    end
    return h
end

function count_ints_two_pass(indices, ex = nothing)
    l, h = extrema(indices)
    n = h - l + 1
    @floop ex begin
        @init hist = zeros(Int, n)
        for i in indices
            hist[i-l+1] += 1
        end
        @combine hist .+= _
    end
    return hist
end

function test_count_ints_two_pass()
    @testset "$(repr(ex))" for ex in [SequentialEx(), nothing, ThreadedEx(basesize = 1)]
        @test countmap_two_pass(1:3, ex) == [1, 1, 1]
        @test countmap_two_pass([1, 2, 4, 1], ex) == [2, 1, 0, 1]
        @test count_ints_two_pass(1:3, ex) == [1, 1, 1]
        @test count_ints_two_pass([1, 2, 4, 1], ex) == [2, 1, 0, 1]
    end
end

function count_ints4(ints; nbins::Val{n} = Val(10), ex = nothing) where {n}
    @floop ex begin
        @init b1 = zero(MVector{n,Int32})
        @init b2 = zero(MVector{n,Int32})
        @init b3 = zero(MVector{n,Int32})
        @init b4 = zero(MVector{n,Int32})
        for (i1, i2, i3, i4) in ints
            @inbounds b1[max(1, min(i1, n))] += 1
            @inbounds b2[max(1, min(i2, n))] += 1
            @inbounds b3[max(1, min(i3, n))] += 1
            @inbounds b4[max(1, min(i4, n))] += 1
        end
        h1 = SVector(b1)
        h2 = SVector(b2)
        h3 = SVector(b3)
        h4 = SVector(b4)

        @combine h1 .+= _
        @combine h2 .= _ .+ _
        @combine h3 += _
        @combine h4 = _ + _
    end
    return (h1, h2, h3, h4)
end

function test_count_ints4()
    @testset "$(repr(ex))" for ex in [SequentialEx(), nothing, ThreadedEx(basesize = 1)]
        @test count_ints4(zip(1:3, 2:4, 3:5, 4:6); ex = ex) == (
            [1, 1, 1, 0, 0, 0, 0, 0, 0, 0],
            [0, 1, 1, 1, 0, 0, 0, 0, 0, 0],
            [0, 0, 1, 1, 1, 0, 0, 0, 0, 0],
            [0, 0, 0, 1, 1, 1, 0, 0, 0, 0],
        )
    end
end

function count_positive_ints(ints; ex = nothing)
    @floop ex begin
        @init hist = Int[]

        for i in ints
            n = length(hist)
            if i > n
                resize!(hist, i)
                hist[n+1:end] .= 0
            end
            @inbounds hist[max(1, i)] += 1
        end

        @combine() do (hist; hist2)
            n = length(hist)
            m = length(hist2)
            if m > n
                n, m = m, n
                hist, hist2 = hist2, hist
            end
            hist[1:m] .+= hist2
        end
    end
    return hist
end

function test_count_positive_ints()
    @testset "$(repr(ex))" for ex in [SequentialEx(), nothing, ThreadedEx(basesize = 1)]
        @test count_positive_ints(1:3; ex = ex) == [1, 1, 1]
        @test count_positive_ints([1, 2, 4, 1]; ex = ex) == [2, 1, 0, 1]
    end
end

#=
using FillArrays
function countmap_one_pass(indices)
    @floop for i in indices
        @init l = nothing
        @init b = [0]
        if l === nothing
            l = i
        elseif i < l
            splice!(b, 1:0, Zeros(l - i + 1))
            l = i
        end
        b[i - l + 1] += 1
        @combine() do (h; b), (l; l2)
        end
    end
end
=#

end  # module
