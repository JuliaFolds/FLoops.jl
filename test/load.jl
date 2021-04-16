try
    using FLoopsTests
    true
catch
    false
end || begin
    push!(LOAD_PATH, @__DIR__)
    using FLoopsTests
end
