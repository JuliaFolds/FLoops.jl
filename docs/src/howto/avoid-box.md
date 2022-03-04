# [How to avoid `Box`?](@id avoid-box)

FLoops.jl may complain about `HasBoxedVariableError`. For a quick prototyping,
calling [`FLoops.assistant(false)`](@ref FLoops.assistant) to disable the
error/warning may be useful.  However, it is also easy to avoid this problem if
you understand a few patterns as explained below:

* ["Leaked variables" ⇒ use `local`](@ref leaked-variables)
* ["Uncertain values" ⇒ use `let`](@ref uncertain-values)
* ["Not really a data race" ⇒ use `Ref`](@ref not-really-a-data-race)

## ["Leaked variables" ⇒ use `local`](@id leaked-variables)

`HasBoxedVariableError` can occur when "leaked" variables are causing data
races.  Consider the following example:

```julia
function leaked_variable_example(xs)
    a = xs[begin]
    b = xs[end]
    c = (a + b) / 2
    @floop for x in xs
        a = max(x, c)
        @reduce s += a
    end
    return s
end
```

Calling this function causes `HasBoxedVariableError`:

```julia-console
julia> FLoops.assistant(:error);

julia> leaked_variable_example(1:2)
ERROR: HasBoxedVariableError: Closure ... has 1 boxed variable: a
```

This occurs because the variable `a` is assigned before `@floop` by `a =
xs[begin]` and inside `@floop` by `a = max(x, c)`.  However, since the
assignment inside `@floop` can occur in parallel, this is a data race.  We can
avoid this issue easily by making `a` local inside the loop:

```julia
function leaked_variable_example_fix1(xs)
    a = xs[begin]
    b = xs[end]
    c = (a + b) / 2
    @floop for x in xs
        local a = max(x, c)   # note `local`
        @reduce s += a
    end
    return s
end
```

Alternatively, we can use a different name:

```julia
function leaked_variable_example_fix2(xs)
    a = xs[begin]
    b = xs[end]
    c = (a + b) / 2
    @floop for x in xs
        d = max(x, c)   # not `a`
        @reduce s += d
    end
    return s
end
```

or limit the scope of `a` used for calculating `c`:

```julia
function leaked_variable_example_fix3(xs)
    c = let a = xs[begin], b = xs[end]  # limit the scope of `a`
        (a + b) / 2
    end
    @floop for x in xs
        a = max(x, c)
        @reduce s += a
    end
    return s
end
```

## ["Uncertain values" ⇒ use `let`](@id uncertain-values)

!!! note
    This is a known limitation as of Julia 1.8-DEV. This documentation may not
    be accurate in the future version of Julia. For more information, see:
    [performance of captured variables in closures · Issue #15276 · JuliaLang/julia](https://github.com/JuliaLang/julia/issues/15276)

`HasBoxedVariableError` can also occur when Julia is uncertain about the value
of some variables in the scope surrounding `@floop` (i.e., there are multiple
binding locations).  For example:

```julia
function uncertain_value_example(xs; flag = false)
    if flag
        a = 0
    else
        a = 1
    end
    @floop for x in xs
        x += a
        @reduce s += x
    end
    return s
end
```

This can be fixed by using `let` to ensure that the variable `a` does not change
while executing `@floop`. (Julia can be sure that the variable is not updated
when it is assigned only once.)

```julia
function uncertain_value_example_fix(xs; flag = false)
    if flag
        a = 0
    else
        a = 1
    end
    let a = a  # "quench" the value of `a`
        @floop for x in xs
            x += a
            @reduce s += x
        end
        return s
    end
end
```

## ["Not really a data race" ⇒ use `Ref`](@id not-really-a-data-race)

It is conceptually sound to assign to the variables in an outer scope of
`@floop` if it is ensured that the race does not occur.  For example, in the
following example, `found = i` can be executed at most once since the elements
of `xs` are all distinct:

```julia
function non_data_race_example(xs::UnitRange; ex = nothing)
    local found = nothing
    @floop ex for (i, x) in pairs(xs)
        if x == 1
            found = i
        end
    end
    return found
end
```

However, FLoops.jl also complains about `HasBoxedVariableError` when executing
this function.  We can fix this by using `Ref`:

```julia
function non_data_race_example_fix(xs::UnitRange; ex = nothing)
    found = Ref{Union{Int,Nothing}}(nothing)
    @floop ex for (i, x) in pairs(xs)
        if x == 1
            found[] = i
        end
    end
    return found[]
end
```
