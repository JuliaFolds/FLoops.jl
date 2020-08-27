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

# Note that `op=` syntax does not have this restriction:

@test begin
    @floop for x in 1:10
        @reduce(a += x, b *= x)
    end
    (a, b)
end == (55, 3628800)

# The argument should be manually duplicated when using the same
# variable that would be merged into multiple accumulators:

@test begin
    @floop for x in 1:10
        y = x
        @reduce() do (a; x), (b; y)
            a += x
            b *= y
        end
    end
    (a, b)
end == (55, 3628800)

# If two accumulators do not interact as in the case above, it is
# recommended to use two `@reduce() do` blocks to clarify that they
# are independent reductions:

@test begin
    @floop for x in 1:10
        @reduce() do (a; x)
            a += x
        end
        @reduce() do (b; x)
            b *= x
        end
    end
    (a, b)
end == (55, 3628800)
