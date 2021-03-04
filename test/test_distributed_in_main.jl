module TestDistributedInMain
using PerformanceTestTools
PerformanceTestTools.@include_foreach("__test_distributed_in_main.jl", [[`--procs=1`]])
end  # module
