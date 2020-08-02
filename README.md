# FLoops: `foldl` for humans™

[![GitHub Actions](https://github.com/JuliaFolds/FLoops.jl/workflows/Run%20tests/badge.svg)](https://github.com/JuliaFolds/FLoops.jl/actions?query=workflow%3A%22Run+tests%22)

[FLoops.jl](https://github.com/JuliaFolds/FLoops.jl) provides a macro
`@floop`.  It can be used to generate a fast generic iteration over
complex collections.

## Usage

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

When accumulating into pre-defined variables, simply list them between
`begin` and `for`.  `@floop` also works with multiple accumulators.

```julia
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

The `begin ... end` block can be omitted if the `for` loop does not
require local variables to carry the state:

```julia
julia> @floop for x in 1:3
           @show x
       end
x = 1
x = 2
x = 3
```

## How it works

`@floop` works by converting the native Julia `for` loop syntax to
`foldl` defined by
[Transducers.jl](https://github.com/JuliaFolds/Transducers.jl).  Unlike
`foldl` defined in `Base`, `foldl` defined by Transducers.jl is
[powerful enough to cover the `for` loop semantics and more](https://tkf.github.io/Transducers.jl/dev/manual/#Base.foreach).

## Supported syntaxes

### `continue`

```julia
julia> @floop for x in 1:3
           if x == 1
               println("continue")
               continue
           end
           @show x
       end
continue
x = 2
x = 3
```

### `break`

```julia
julia> @floop for x in 1:3
           @show x
           if x == 2
               println("break")
               break
           end
       end
x = 1
x = 2
break
```

### `return`

```julia
julia> function demo()
           @floop for x in 1:3
               @show x
               if x == 2
                   return "return"
               end
           end
       end
       demo()
x = 1
x = 2
"return"
```

### `@goto`

```julia
julia> begin
       @floop for x in 1:3
           x == 1 && @goto L1
           @show x
           if x == 2
               @goto L2
           end
           @label L1
       end
       println("This is not going to be printed.")
       @label L2
       println("THIS is going to be printed.")
       end
x = 2
THIS is going to be printed.
```
