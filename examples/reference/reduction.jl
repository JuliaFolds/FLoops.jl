# # Parallelizable reduction using `@reduce`

# !!! warning
#
#     This page is still work-in-progress.

using FLoops

using LiterateTest                                                     #src
using Test                                                             #src

# ## [`@reduce() do ... end` syntax](@id ref-reduce-do)

@test begin
    @floop for x in 1:10
        y = 2x
        @reduce() do (acc; y)
            acc += y
        end
    end
    acc
end == 110

# ### Argument symbols must be unique within a `@reduce` block

@testset_error @eval try
    @floop for x in 1:10
        @reduce() do (a; x), (b; x)
            a += x
            b *= x
        end
    end
catch err
    @test err isa Exception
end
