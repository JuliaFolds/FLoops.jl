module TestCore

using FLoops
using Test

function test_two_states()
    xs = 1:10
    @floop begin
        s = 0
        p = 1
        for x in xs
            s += x
            p *= x
        end
    end
    @test s == sum(xs)
    @test p == prod(xs)
end

function test_complex_assignments()
    xs = 1:10
    @floop begin
        s = 0
        p = s + 1
        for x in xs
            s += x
            p *= x
        end
    end
    @test s == sum(xs)
    @test p == prod(xs)
end

function test_no_states()
    xs = 1:10
    ys = similar(xs)
    @floop begin
        for (i, x) in enumerate(xs)
            ys[i] = 2x
        end
    end
    @test ys == 2 .* xs
end

function test_at_inbounds()
    xs = 1:10
    @floop begin
        s = 0
        @inbounds for x in xs
            s += x
        end
    end
    @test s == sum(xs)
end

function test_function()
    xs = 1:10
    @floop begin
        s = 0
        @inbounds for x in xs
            f() = return s + x
            s = f()
        end
    end
    @test s == sum(xs)
end

function test_let_and_break()
    function demo(xs)
        @floop begin
            s = 0
            p = 1
            for x in xs
                s += x
                p *= x
                let p = x
                    if p == 5
                        s = 0
                        break
                    end
                end
            end
        end
        return (s, p)
    end
    @test demo(1:10) == (0, prod(1:5))
    @test demo(1:4) == (sum(1:4), prod(1:4))
end

function test_let_and_continue()
    function demo(xs)
        @floop begin
            s = 0
            p = 1
            for x in xs
                let p = x
                    if p == 5
                        s = 0
                        continue
                    end
                end
                s += x
                p *= x
            end
        end
        return (s, p)
    end
    @test demo(1:10) == (sum(6:10), prod(1:10) ÷ 5)
    @test demo(1:4) == (sum(1:4), prod(1:4))
end

function test_continue()
    xs = 1:3
    ys = []
    @floop begin
        for x in xs
            x == 1 && continue
            push!(ys, x)
        end
    end
    @test ys == [2, 3]
end

function test_break()
    xs = 1:3
    ys = []
    @floop begin
        for x in xs
            push!(ys, x)
            x == 2 && break
        end
    end
    @test ys == [1, 2]
end

function test_return()
    function demo()
        ys = []
        @floop begin
            for x in 1:3
                push!(ys, x)
                if x == 2
                    return ys
                end
            end
        end
    end
    @test demo() == [1, 2]
end

function test_product()
    xs = 1:10
    ys = 2:3:15
    actual = []
    @floop begin
        for x in xs, y in ys
            push!(actual, (y, x))
        end
    end
    desired = []
    for x in xs, y in ys
        push!(desired, (y, x))
    end
    @test actual == desired
end

function test_triangular_2()
    xs = 1:10
    actual = []
    @floop begin
        for x in xs, y in x:2:10
            push!(actual, (y, x))
        end
    end
    desired = []
    for x in xs, y in x:2:10
        push!(desired, (y, x))
    end
    @test actual == desired
end

function test_triangular_3()
    xs = 1:10
    actual = []
    @floop begin
        for x in xs, y in x:2:10, z in x:y:20
            push!(actual, (y, x, z))
        end
    end
    desired = []
    for x in xs, y in x:2:10, z in x:y:20
        push!(desired, (y, x, z))
    end
    @test !isempty(actual)  # make sure it tests _something_
    @test actual == desired
end

function test_internal_goto()
    xs = 1:10
    @floop begin
        s = 0
        for x in xs
            @goto a
            s += x
            @label a
        end
    end
    @test s == 0
end

function test_external_goto()
    xs = 1:10
    @floop begin
        s = 0
        for x in xs
            s += x
            s > 5 && @goto a
        end
    end
    @label a
    @test s == 6
end

end  # module
