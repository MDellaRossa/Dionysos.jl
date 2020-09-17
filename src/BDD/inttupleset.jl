"""
    mutable struct IntTupleSet <: AbstractSet{NTuple{N,<:Integer} where N}

Same as `Base.Set{NTuple{N,<:Integer} where N}` but with `CUDD`.
"""
mutable struct IntTupleSet{N,T<:Integer} <: AbstractSet{NTuple{N,T}}
    cp::CartesianProduct
    slices::Vector{Int}
end

function IntTupleSet{N,T}() where {N,T}
    @assert N > 0
    cp = CartesianProduct(N)
    slices_ = [1:N]
    root = _Zero(mng); _Ref(root)
    add_root(cp, root, slices)
    set = IntTupleSet{N,T}(cp, slices)
    finalizer(set -> finalize(set.cp), set)
    return set
end
IntTupleSet{N}() where N = IntTupleSet{N,Int}()

function IntTupleSet{T}(cp::CartesianProduct, slices::AbstractArray{Int}) where T
    N = length(slices)
    @assert allunique(slices)
    root = _Zero(mng); _Ref(root)
    add_root(cp, root, slices)
    return IntTupleSet{N,T}(cp, slices)
end
IntTupleSet(cp::CartesianProduct, slices::AbstractArray{Int}) = IntTupleSet{Int}()

Base.eltype(::Type{IntTupleSet{N,T}}) where {N,T} = NTuple{N,T}
Base.empty(::IntTupleSet{N}, ::Type{T}=Int) where {N,T} = IntTupleSet{N,T}()
Base.emptymutable(::IntTupleSet{N}, ::Type{T}=Int) where {N,T} = IntTupleSet{N,T}()

function _phases1!(set::IntTupleSet, x)
    cp = set.cp
    for (i, e) in zip(set.slices, x)
        indices = cp.indices_[i]
        auxindices = empty!(cp.auxindices_[i])
        phases = cp.phases1_[i]
        auxphases = empty!(cp.auxphases_[i])
        _compute_phases!(cp.mng, phases, indices, auxphases, auxindices, e)
    end
end

# Returns the first i for which there is not enough bits to represent x[i];
# Returns 0 if there is no such i.
function _phases1_trunc!(set::IntTupleSet, x)
    for i in eachindex(set.indices_)
        !_compute_phases_trunc!(set.phases1_[i], x[i]) && return i
    end
    return 0
end

# TODO: Can we improve this?
@inline _incr_(e::T, i, j) where T = i == j ? zero(T) : (i == j + 1 ? e + one(T) : e)
function _increment(x::NTuple{N}, j) where N
    return ntuple(i -> _incr_(x[i], i, j), Val(N))
end

Base.iterate(set::IntTupleSet{N,T}) where {N,T} = iterate(set, ntuple(i -> zero(T), Val(N)))
function Base.iterate(set::IntTupleSet{N}, state::NTuple{N}) where N
    I = _phases1_trunc!(set, state)
    I == N && return nothing
    I == 0 && _eval_phases(set) && return (state, _increment(state, 0))
    return iterate(set, _increment(state, I))
end
