module BenchSum

using BenchmarkTools
using BlockArrays: mortar
using FLoops
using FillArrays: Zeros

function sum_for(xs)
    acc = 0.0
    for x in xs
        acc += x
    end
    return acc
end

function sum_floop(xs)
    @floop begin
        acc = 0.0
        @simd for x in xs
            acc += x
        end
    end
    return acc
end

const SUITE = BenchmarkGroup()

floats = randn(1000)
dataset = [
    "Vector" => floats,
    "filter" => Iterators.filter(!ismissing, ifelse.(floats .> 2, missing, floats)),
    "flatten" => Iterators.flatten((floats, (1, 2), 3:4, 5:0.2:6, Zeros(1000))),
    "BlockVector" => mortar([floats, floats]),
]

for (label, xs) in dataset
    @assert sum_for(xs) ≈ sum_floop(xs)
    s1 = SUITE[:label=>label] = BenchmarkGroup()
    s1[:impl=>"for"] = @benchmarkable sum_for($xs)
    s1[:impl=>"floop"] = @benchmarkable sum_floop($xs)
end

end  # module
BenchSum.SUITE
