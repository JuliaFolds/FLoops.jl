import FLoops

let sumwith,
    smoketest

    function sumwith(f, xs, ex = nothing)
        FLoops.@floop ex for x in xs
            FLoops.@reduce s += f(x) 
        end
        return s
    end

    function smoketest(ex = nothing)
        sumwith(identity, 1:10, ex)
    end

    (
        sumwith = sumwith,
        smoketest = smoketest,  # just run all functions
    )
end
