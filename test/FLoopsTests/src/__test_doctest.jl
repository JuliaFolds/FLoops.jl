import FLoops
using Documenter: doctest

# Workaround `UndefVarError: FLoops not defined`
@eval Main import FLoops

doctest(FLoops, manual = true)
