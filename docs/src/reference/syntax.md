# Syntax supported by `@floop`

```@meta
DocTestSetup = quote
    using FLoops
end
```

## `continue`

```jldoctest
julia> @floop begin
           for x in 1:3
               if x == 1
                   println("continue")
                   continue
               end
               @show x
           end
       end
continue
x = 2
x = 3
```

## `break`

```jldoctest
julia> @floop begin
           for x in 1:3
               @show x
               if x == 2
                   println("break")
                   break
               end
           end
       end
x = 1
x = 2
break
```

## `return`

```jldoctest
julia> function demo()
           @floop begin for x in 1:3
                   @show x
                   if x == 2
                       return "return"
                   end
               end
           end
       end
       demo()
x = 1
x = 2
"return"
```

## `@goto`

```jldoctest
julia> begin
       @floop begin
           for x in 1:3
               x == 1 && @goto L1
               @show x
               if x == 2
                   @goto L2
               end
               @label L1
           end
       end
       println("This is not going to be printed.")
       @label L2
       println("THIS is going to be printed.")
       end
x = 2
THIS is going to be printed.
```

```@meta
DocTestSetup = nothing
```
