# Julia 1.7 doesn't infer this:
has_boxed_variables_f(f::F) where {F} =
    _any(ntuple(i -> fieldtype(typeof(f), i) <: Core.Box, Val(nfields(f)))...)

@generated has_boxed_variables_g(::F) where {F} = any(t -> t <: Core.Box, fieldtypes(F))

if VERSION < v"1.7-"
    const has_boxed_variables = has_boxed_variables_f
else
    const has_boxed_variables = has_boxed_variables_g
end

function verify_no_boxes(f::F) where {F}
    has_boxed_variables(f) && throw(HasBoxedVariableError(f))
    return
end

struct HasBoxedVariableError <: Exception
    f::Any
end

function Base.showerror(io::IO, err::HasBoxedVariableError)
    f = err.f
    varnames = [
        fieldname(typeof(f), i) for i in 1:nfields(f) if fieldtype(typeof(f), i) <: Core.Box
    ]

    print(io, "HasBoxedVariableError: Closure ")
    printstyled(io, nameof(f); color = :cyan)
    print(io, " (defined in ")
    printstyled(io, parentmodule(f); color = :cyan)
    print(io, ")")
    print(io, " has ", length(varnames), " boxed ")
    if length(varnames) == 1
        print(io, "variable:")
    else
        print(io, "variables:")
    end

    isfirst = true
    for v in varnames
        if isfirst
            isfirst = false
            print(io, ' ')
        else
            print(io, ", ")
        end
        printstyled(io, v; bold = true, color = :red)
    end

    println(io)
    printstyled(io, "HINT:", bold = true, color = :magenta)
    var = get(varnames, 1, :x)
    print(io, " Consider adding declarations such as `")
    printstyled(io, "local ", var; color = :cyan)
    print(io, "` at the narrowest possible scope required.")

    println(io)
    printstyled(io, "NOTE:", bold = true, color = :light_black)
    printstyled(
        io,
        " This is very likely required for avoiding data races.",
        " If boxing the variables is intended, use `Ref{Any}(...)`",
        " instead.";
        color = :light_black,
    )
    # "To ignore this error, pass `allow_boxing = Val(true)` to the executor."
end

function _make_closure_with_a_box()
    local a
    set(b) = (z = a; a = b; z)
    return set
end

function _make_closure_without_a_box(a = 1)
    add(b) = a + b
    return add
end

_box_detection_works() =
    has_boxed_variables(_make_closure_with_a_box()) &&
    !has_boxed_variables(_make_closure_without_a_box())

if try
    _box_detection_works()
catch err
    @error(
        "Error in `has_boxed_variables`. Disabling boxing detection.",
        exception = (err, catch_backtrace())
    )
    false
end
    const _verify_no_boxes = verify_no_boxes
else
    # Since `Core.Box` is internal, we can't rely on that it exists.
    const _verify_no_boxes = identity
end
