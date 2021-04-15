module FLoopsTests
using Test

for file in sort([
    file for file in readdir(@__DIR__) if match(r"^test_.*\.jl$", file) !== nothing
])
    include(file)
end

function collect_modules(root::Module = @__MODULE__)
    modules = Module[]
    for n in names(root, all = true)
        m = getproperty(root, n)
        m isa Module || continue
        m === root && continue
        startswith(string(nameof(m)), "Test") || continue
        push!(modules, m)
    end
    return modules
end

this_project() = joinpath(dirname(@__DIR__), "Project.toml")

function is_in_path()
    project = this_project()
    paths = Base.load_path()
    project in paths && return true
    realproject = realpath(project)
    realproject in paths && return true
    matches(path) = path == project || path == realproject
    return any(paths) do path
        matches(path) || matches(realpath(path))
    end
end

function with_project(f)
    is_in_path() && return f()
    load_path = copy(LOAD_PATH)
    push!(LOAD_PATH, this_project())
    try
        f()
    finally
        append!(empty!(LOAD_PATH), load_path)
    end
end

function runtests(modules = collect_modules())
    with_project() do
        runtests_impl(modules)
    end
end

function runtests_impl(modules)
    @testset "$(nameof(m))" for m in modules
        if m === TestDoctest
            if lowercase(get(ENV, "JULIA_PKGEVAL", "false")) == "true"
                @info "Skipping doctests on PkgEval."
                continue
            elseif VERSION >= v"1.6-"
                @info "Skipping doctests on Julia $VERSION."
                continue
            end
        end
        tests = map(names(m, all = true)) do n
            n == :test || startswith(string(n), "test_") || return nothing
            f = getproperty(m, n)
            f !== m || return nothing
            parentmodule(f) === m || return nothing
            applicable(f) || return nothing  # removed by Revise?
            return f
        end
        filter!(!isnothing, tests)
        @testset "$f" for f in tests
            f()
        end
    end
end

end  # module
