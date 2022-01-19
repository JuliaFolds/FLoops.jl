# Julia 1.7 doesn't infer this:
has_boxed_variables_f(f::F) where {F} =
    _any(ntuple(i -> fieldtype(typeof(f), i) <: Core.Box, Val(nfields(f)))...)

@generated has_boxed_variables_g(::F) where {F} = any(t -> t <: Core.Box, fieldtypes(F))

if VERSION < v"1.7-"
    const has_boxed_variables = has_boxed_variables_f
else
    const has_boxed_variables = has_boxed_variables_g
end

function verify_no_boxes(f::F, context) where {F}
    has_boxed_variables(f) && handle_boxed_variables(f, context())
    return
end

baremodule AssistantMode
using Base: @enum, UInt8
@enum Kind::UInt8 begin
    ignore
    warn
    warn_always
    error
end
end

const ASSISTANT_MODE = Ref(AssistantMode.warn)

struct SetAssistantResult
    old::AssistantMode.Kind
    new::AssistantMode.Kind
end

"""
    FLoops.assistant(mode::Symbol)
    FLoops.assistant(enable::Bool)

Set assistant mode; i.e., what to do when FLoops.jl finds a problematic usage
pattern.

Assistant modes:

* `:ignore`: do nothing
* `:warn`: print warning once
* `:warn_always`: print warning always
* `:error`: throw an error

`FLoops.assistant(false)` is equivalent to `FLoops.assistant(:ignore)` and
`FLoops.assistant(true)` is equivalent to `FLoops.assistant(:warn)`.
"""
assistant
function assistant(mode::Symbol)
    m = nothing
    if isdefined(AssistantMode, mode)
        m = getproperty(AssistantMode, mode)
    end
    if !(m isa AssistantMode.Kind)
        error(
            "invalid mode: ",
            mode,
            " (must be one of `:ignore`, `:warn`, `:warn_always`, and `:error`)",
        )
    end
    p = ASSISTANT_MODE[]
    ASSISTANT_MODE[] = m
    return SetAssistantResult(p, m)
end

assistant(enable::Bool) = enable ? assistant(:warn) : assistant(:ignore)

function Base.show(io::IO, ::MIME"text/plain", result::SetAssistantResult)
    printstyled(io, "FLoops.assistant"; color = :blue)
    print(io, ":")
    print(io, "\n  old mode: ", result.old)
    print(io, "\n  new mode: ", result.new)
end

function handle_boxed_variables(f, context)
    mode = ASSISTANT_MODE[]
    mode == AssistantMode.ignore && return

    err = HasBoxedVariableError(f)
    if mode == AssistantMode.error
        throw(err)
    elseif mode == AssistantMode.warn || mode == AssistantMode.warn_always
        ctx = context.ctx::MacroContext
        @warn(
            "Correctness and/or performance problem detected",
            error = err,
            _module = ctx.module_,
            _file = string(something(ctx.source.file, "none")),
            _line = ctx.source.line,
            _id = Symbol(context.id, mode == AssistantMode.warn ? :_once : :_always),
            maxlog = mode == AssistantMode.warn ? 1 : nothing,
        )
    else
        error("unknown mode: ", mode)
    end
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

    println(io)
    printstyled(io, "NOTE:", bold = true, color = :light_black)
    printstyled(
        io,
        " To disable this ",
        ASSISTANT_MODE[] == AssistantMode.error ? "error" : "warning",
        ", call `";
        color = :light_black,
    )
    printstyled(io, "FLoops.assistant(false)"; bold = true, color = :light_black)
    printstyled(io, "`."; color = :light_black)
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
    const _verify_no_boxes = donothing
end
