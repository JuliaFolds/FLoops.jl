module TestCheckboxes

using FLoops:
    _box_detection_works,
    _make_closure_with_a_box,
    _make_closure_without_a_box,
    verify_no_boxes,
    HasBoxedVariableError
using Test

function _make_closure_with_two_boxes()
    local a
    local b = 1
    set(v) = (z = a; a = b; b = v; z)
    return set
end

@testset "_box_detection_works" begin
    @test _box_detection_works()
end

@testset "verify_no_boxes" begin
    @test (verify_no_boxes(_make_closure_without_a_box()); true)
    f = _make_closure_with_a_box()
    @test_throws HasBoxedVariableError(f) verify_no_boxes(f)
end

@testset "HasBoxedVariableError" begin
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

end  # module
