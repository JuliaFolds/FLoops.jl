if get(ENV, "CI", "false") == "true"
    using Distributed
    #! format: off
    VERSION < v"1.8-" && # workaround the hang in CI
    if nprocs() < 4
        addprocs(4 - nprocs())
    end
    #! format: on
end

using TestFunctionRunner
TestFunctionRunner.@run
