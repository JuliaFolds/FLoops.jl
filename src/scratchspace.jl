""" A singleton type that indicates `ScratchSpace` is deallocated. """
struct Cleared end

"""
    ScratchSpace(f::F, value::T)
    ScratchSpace{F,T}(f::F)

An object for appropriately caching the `value` returned from `f`. The
`value` is thrown away when `serialize`d.

Construct this by `x = ScratchSpace(f, f())`. At the use site, update the
variable with `x = allocated(x)` and then fetch the value by `x.value`.
"""
struct ScratchSpace{F,T}
    f::F
    value::Union{T,Cleared}
    ScratchSpace(f::F, value::T) where {F,T} = new{F,T}(f, value)
    # ScratchSpace{F,T}(f::F, value::T) where {F,T} = new{F,T}(f, value)
    ScratchSpace{F,T}(f::F) where {F,T} = new{F,T}(f, Cleared())  # deallocate
end
# Note: Using `::Union{T,Cleared}` so that serialize-deserialize does not
# change the type (after throwing away the `.value`). It seems that the
# compiler can optimize away the type-instability.

@inline function allocate(x::ScratchSpace)
    if x.value isa Cleared
        return ScratchSpace(x.f, x.f())
    else
        return x
    end
end

# Idea: use this instead of `x.value` to help(?) the compiler
#=
@inline function getvalue(x::ScratchSpace)
    value = x.value
    if value isa Cleared
        return x.f()
    else
        return value
    end
end
=#

# Throw away temporary object `.value` when crossing the wire (i.e., called via
# Distributed).
Serialization.serialize(ser::S, x::ScratchSpace{F,T}) where {S<:AbstractSerializer,F,T} =
    invoke(Serialization.serialize, Tuple{S,Any}, ser, ScratchSpace{F,T}(x.f))
