# FLoops: `fold` for humans™

[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://juliafolds.github.io/FLoops.jl/dev)
[![GitHub Actions](https://github.com/JuliaFolds/FLoops.jl/workflows/Run%20tests/badge.svg)](https://github.com/JuliaFolds/FLoops.jl/actions?query=workflow%3A%22Run+tests%22)

[FLoops.jl](https://github.com/JuliaFolds/FLoops.jl) provides a macro
`@floop`.  It can be used to generate a fast generic iteration over
complex collections.

## Usage

# Sequential (single-thread) loops

Simply wrap a `for` loop and its initialization part by `@floop`:

```julia
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

For more examples, see
[sequential loops tutorial](https://juliafolds.github.io/FLoops.jl/dev/tutorials/sequential/).

# Parallel loop

Parallel loops require additional syntax `@reduce`.

```julia
julia> @floop for (x, y) in zip(1:3, 1:2:6)
           a = x + y
           b = x - y
           @reduce(s += a, t += b)
       end
       (s, t)
(15, -3)
```

For more examples, see
[parallel loops tutorial](https://juliafolds.github.io/FLoops.jl/dev/tutorials/parallel/).

## How it works

`@floop` works by converting the native Julia `for` loop syntax to
`foldl` defined by
[Transducers.jl](https://github.com/JuliaFolds/Transducers.jl).  Unlike
`foldl` defined in `Base`, `foldl` defined by Transducers.jl is
[powerful enough to cover the `for` loop semantics and more](https://tkf.github.io/Transducers.jl/dev/manual/#Base.foreach).
