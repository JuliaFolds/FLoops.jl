if get(ENV, "CI", "false") == "true"
    using Distributed
    VERSION < v"1.8-" && # workaround the hang in CI
    if nprocs() < 4
        addprocs(4 - nprocs())
    end
end

using TestFunctionRunner
TestFunctionRunner.@run
