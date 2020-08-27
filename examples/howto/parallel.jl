# # How to write _X_ in parallel.

using FLoops

using Test                                                             #src

# !!! warning
#
#     This page is still work-in-progress.

# ## In-place mutation
#
# Mutable containers can be allocated in the `init` expressions
# (`zeros(3)` in the example below):

@test begin
    @floop for x in 1:10
        xs = [x, 2x, 3x]
        @reduce() do (ys = zeros(3); xs)
            ys .+= xs
        end
    end
    ys
end == [55, 110, 165]

# Mutating objects allocated in the `init` expressions is not data
# race because each basecase "owns" such mutable objects.  However, it
# is incorrect to mutate objects created outside `init` expressions.
#
# !!! note
#
#     Technically, it is correct to mutate objects in the loop body if
#     the objects are protected by a lock.  However, it means that the
#     code block protected by the lock can only be executed by a
#     single task.  For efficient data parallel loops, it is highly
#     recommended to use **non**-thread-safe data collection (i.e., no
#     lock) and construct the `@reduce` block that efficiently merge
#     two mutable objects.

# ### INCORRECT EXAMPLE

# This example has data race because the array `ys0` is shared across
# all base cases and mutated in parallel.

ys0 = zeros(3)
@floop for x in 1:10
    xs = [x, 2x, 3x]
    @reduce() do (ys = ys0; xs)
        ys .+= xs
    end
end
