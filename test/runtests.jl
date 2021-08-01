if get(ENV, "CI", "false") == "true"
    using Distributed
    if nprocs() < 4
        addprocs(4 - nprocs())
    end
end

using TestFunctionRunner
TestFunctionRunner.@run
