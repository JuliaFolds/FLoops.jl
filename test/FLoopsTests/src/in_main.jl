import FLoops

let sumwith, useinit, smoketest

    function sumwith(f, xs, ex = nothing)
        FLoops.@floop ex for x in xs
            FLoops.@reduce s += f(x)
        end
        return s
    end

    function useinit(xs, ex = nothing)
        T = eltype(xs)
        FLoops.@floop ex for x in xs
            FLoops.@init v = zeros(T, 1)
            v[1] = x
            FLoops.@reduce s += v[1]
        end
        return s
    end

    function smoketest(ex = nothing)
        sumwith(identity, 1:10, ex)
    end

    (
        sumwith = sumwith,
        useinit = useinit,
        smoketest = smoketest,  # just run all functions
    )
end
