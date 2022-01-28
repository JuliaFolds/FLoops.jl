module TestCombine

using FLoops
using MicroCollections
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

function test_countmap_two_pass()
    @testset "$(repr(ex))" for ex in [SequentialEx(), nothing, ThreadedEx(basesize = 1)]
        @test countmap_two_pass(1:3, ex) == [1, 1, 1]
        @test countmap_two_pass([1, 2, 4, 1], ex) == [2, 1, 0, 1]
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
