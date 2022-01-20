# [Sequential (single-thread) loops](@id tutorials-sequential)

Simply wrap a `for` loop and its initialization part by `@floop`:

```jldoctest
julia> using FLoops  # exports @floop macro

julia> @floop begin
           s = 0
           for x in 1:3
               s += x
           end
       end
       s
6
```

When accumulating into pre-defined variables, simply list them between
`begin` and `for`.  `@floop` also works with multiple accumulators.

```jldoctest
julia> using FLoops

julia> s = 6;

julia> @floop begin
           s
           p = 1
           for x in 4:5
               s += x
               p *= x
           end
       end
       s
15

julia> p
20
```
