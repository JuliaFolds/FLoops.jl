module TestCheckboxes

using FLoops:
    FLoops,
    HasBoxedVariableError,
    MacroContext,
    _box_detection_works,
    _make_closure_with_a_box,
    _make_closure_without_a_box,
    has_boxed_variables,
    verify_no_boxes
using Test

function with_assistant(f, mode)
    result = FLoops.assistant(mode)
    try
        f()
    finally
        FLoops.assistant(Symbol(result.old))
    end
end

function _make_closure_with_two_boxes()
    local a
    local b = 1
    set(v) = (z = a; a = b; b = v; z)
    return set
end

function test__box_detection_works()
    @test _box_detection_works()
end

dummy_context() = (ctx = MacroContext(LineNumberNode(0), @__MODULE__), id = :dummy)

function test_assistant()
    @test (verify_no_boxes(_make_closure_without_a_box(), dummy_context); true)

    f = _make_closure_with_a_box()
    with_assistant(:error) do
        @test_throws HasBoxedVariableError(f) verify_no_boxes(f, dummy_context)
    end
    with_assistant(true) do
        @test_logs (:warn, r"Correctness .*") verify_no_boxes(f, dummy_context)
    end
    with_assistant(:warn) do
        @test_logs (:warn, r"Correctness .*") verify_no_boxes(f, dummy_context)
    end
    with_assistant(:warn_always) do
        @test_logs (:warn, r"Correctness .*") verify_no_boxes(f, dummy_context)
    end
    with_assistant(:ignore) do
        @test_logs verify_no_boxes(f, dummy_context)
    end
    with_assistant(false) do
        @test_logs verify_no_boxes(f, dummy_context)
    end

    result = with_assistant(:error) do
        FLoops.assistant(:warn)
    end
    msg = sprint(show, "text/plain", result)
    @test occursin("FLoops.assistant", msg)
    @test occursin("old mode: error", msg)
    @test occursin("new mode: warn", msg)

    err = try
        FLoops.assistant(:INVALID_MODE)
        nothing
    catch e
        e
    end
    @test err isa Exception
    msg = sprint(showerror, err)
    @test occursin("invalid mode:", msg)
end

function test_HasBoxedVariableError()
    @testset "one box" begin
        err = HasBoxedVariableError(_make_closure_with_a_box())
        @debug "Example `HasBoxedVariableError`" err
        msg = sprint(showerror, err)
        @test occursin("Consider adding declarations such as `local a`", msg)
        @test occursin("1 boxed variable:", msg)
        @test occursin(r"\b a \b"x, msg)
    end
    @testset "two boxes" begin
        err = HasBoxedVariableError(_make_closure_with_two_boxes())
        @debug "Example `HasBoxedVariableError`" err
        msg = sprint(showerror, err)
        @test occursin(r"Consider adding declarations such as `local (a|b)`", msg)
        @test occursin("2 boxed variables:", msg)
        @test occursin(r"\b a \b"x, msg)
        @test occursin(r"\b b \b"x, msg)
    end
end

function with_box_1()
    a = 0
    function closure()
        a += 1
    end
    Val(has_boxed_variables(closure))
end

function with_box_3()
    (a, b, c) = (1, 2, 3)
    function closure()
        c = a + b + c
    end
    Val(has_boxed_variables(closure))
end

function with_box_7()
    (a, b, c, d, e, f, g) = (1, 2, 3, 4, 5, 6, 7)
    function closure()
        g = a + b + c + d + e + f + g
    end
    Val(has_boxed_variables(closure))
end

function with_box_10()
    (a, b, c, d, e, f, g, h, i, j) = (1, 2, 3, 4, 5, 6, 7, 8, 9, 10)
    function closure()
        j = a + b + c + d + e + f + g + h + i + j
    end
    Val(has_boxed_variables(closure))
end

function test_inferrability()
    @test @inferred(with_box_1()) == Val(true)
    @test @inferred(with_box_3()) == Val(true)
    @test @inferred(with_box_7()) == Val(true)
    @test @inferred(with_box_10()) == Val(true)
end

end  # module
