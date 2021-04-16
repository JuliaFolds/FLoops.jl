module TestUtils

using FLoops: _any
using Test

function test_any()
    tf = [false, true]
    @testset for arity in 0:12
        combinations = Iterators.product((tf for _ in 1:arity)...)
        for bools in combinations
            @test _any(bools...) == any(bools)
        end
    end
end

end  # module
