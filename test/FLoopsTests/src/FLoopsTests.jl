module FLoopsTests

using Test

include("utils.jl")

for file in
    sort([file for file in readdir(@__DIR__) if match(r"^test_.*\.jl$", file) !== nothing])
    include(file)
end

end  # module
