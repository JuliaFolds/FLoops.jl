# API

## `@floop`

```@docs
FLoops.@floop
```

## `@reduce`

```@docs
FLoops.@reduce
```

## `@combine`

```@docs
FLoops.@combine
```

## `@init`

```@docs
FLoops.@init
```

## `@completebasecase`

```@docs
FLoops.@completebasecase
```

## [`SequentialEx`, `ThreadedEx` and `DistributedEx` executors](@id executor)

An *executor* controls how a given `@floop` is executed. FLoops.jl re-exports
`SequentialEx`, `ThreadedEx` and `DistributedEx` executors from
Transducers.jl.

See also:
* [`@floop` tutorials on executors](@ref tutorials-executor)
* [Executor section in Transducers.jl's glossary](https://juliafolds.github.io/Transducers.jl/dev/explanation/glossary/#glossary-executor).
* [`Transducers.SequentialEx`](https://juliafolds.github.io/Transducers.jl/dev/reference/manual/#Transducers.SequentialEx)
* [`Transducers.ThreadedEx`](https://juliafolds.github.io/Transducers.jl/dev/reference/manual/#Transducers.ThreadedEx)
* [`Transducers.DistributedEx`](https://juliafolds.github.io/Transducers.jl/dev/reference/manual/#Transducers.DistributedEx)
* [How is a parallel `@floop` executed? What is the scheduling strategy?](@ref faq-exeuctor)

## `FLoops.assistant`

```@docs
FLoops.assistant
```
