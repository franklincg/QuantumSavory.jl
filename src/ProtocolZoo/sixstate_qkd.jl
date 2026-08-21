using Random: rand

export SixStateQKDProt, sixstate_log, sifted_key, qber_estimate

"""
$TYPEDEF

Entanglement-based six-state quantum key distribution protocol.

`SixStateQKDProt` consumes Bell pairs shared by `nodeA` and `nodeB`. Alice and
Bob independently choose one of the three Pauli measurement bases X, Y, or Z.
Only same-basis rounds survive sifting. For the ideal `|Φ⁺⟩` Bell state, X and Z
outcomes are correlated while Y outcomes are anti-correlated, so Bob's Y-basis
bit is flipped before the sifted key is compared.

This primitive models pair selection, destructive measurement, basis sifting,
and raw-key/QBER statistics. Authentication, error correction, privacy
amplification, and attacker models belong to higher protocol layers.

$FIELDS
"""
@kwdef struct SixStateQKDProt <: AbstractProtocol
    """time-and-schedule-tracking instance from `ConcurrentSim`"""
    sim::Simulation
    """a network graph of registers"""
    net::RegisterNet
    """the vertex index of Alice's node"""
    nodeA::Int
    """the vertex index of Bob's node"""
    nodeB::Int
    """time between unsuccessful pair queries and measured rounds (`nothing` waits on tag changes when idle)"""
    period::Union{Float64,Nothing} = 0.1
    """measurement and basis-sifting records; the concrete storage type is private"""
    _log::Vector{@NamedTuple{t::Float64,basisA::Symbol,basisB::Symbol,bitA::Int,bitB::Int,kept::Bool}} =
        @NamedTuple{t::Float64,basisA::Symbol,basisB::Symbol,bitA::Int,bitB::Int,kept::Bool}[]
end

function SixStateQKDProt(sim::Simulation, net::RegisterNet, nodeA::Int, nodeB::Int; kwargs...)
    period = get(kwargs, :period, 0.1)
    (isnothing(period) || period > 0) || throw(ArgumentError("period must be positive or nothing"))
    return SixStateQKDProt(; sim, net, nodeA, nodeB, kwargs...)
end

SixStateQKDProt(net::RegisterNet, nodeA::Int, nodeB::Int; kwargs...) =
    SixStateQKDProt(get_time_tracker(net), net, nodeA, nodeB; kwargs...)

permits_virtual_edge(::Type{SixStateQKDProt}) = true
_protocol_nodes(prot::SixStateQKDProt) = (prot.nodeA, prot.nodeB)

protocol_catalog_metadata(::Type{SixStateQKDProt}) = (
    attachment=:edge,
    attachment_fields=(node_a=:nodeA, node_b=:nodeB),
    required_fields=(),
)

"""Return a copy of all six-state QKD measurement records."""
sixstate_log(prot::SixStateQKDProt) = copy(prot._log)

"""Return Alice's raw sifted key bits from same-basis rounds."""
sifted_key(prot::SixStateQKDProt) = [entry.bitA for entry in prot._log if entry.kept]

"""Estimate QBER from all same-basis rounds measured so far."""
function qber_estimate(prot::SixStateQKDProt)
    kept = [entry for entry in prot._log if entry.kept]
    isempty(kept) && return NaN
    return count(entry -> entry.bitA != entry.bitB, kept) / length(kept)
end

function _sixstate_basis()
    choice = rand(1:3)
    choice == 1 && return (:X, X)
    choice == 2 && return (:Y, Y)
    return (:Z, Z)
end

_sixstate_canonical_bit(basis::Symbol, outcome::Int) =
    basis === :Y ? 1 - (outcome - 1) : outcome - 1

@resumable function (prot::SixStateQKDProt)()
    regA = prot.net[prot.nodeA]
    regB = prot.net[prot.nodeB]

    while true
        queryA = query(
            regA,
            EntanglementCounterpart,
            prot.nodeB,
            ❓,
            ❓;
            locked=false,
            assigned=true,
        )

        if isnothing(queryA)
            if isnothing(prot.period)
                @yield onchange(regA, Tag)
            else
                @yield timeout(prot.sim, prot.period::Float64)
            end
            continue
        end

        pair_id = queryA.tag[4]
        queryB = query(
            regB,
            EntanglementCounterpart,
            prot.nodeA,
            queryA.slot.idx,
            pair_id;
            locked=false,
            assigned=true,
        )
        if isnothing(queryB)
            if isnothing(prot.period)
                @yield onchange(regB, Tag)
            else
                @yield timeout(prot.sim, prot.period::Float64)
            end
            continue
        end

        qA = queryA.slot
        qB = queryB.slot
        @yield lock(qA) & lock(qB)

        # Pair queries are snapshots. Revalidate both reciprocal tags and the pair
        # identifier while the slots are locked before destructive measurement.
        lockedA = query(
            qA,
            EntanglementCounterpart,
            prot.nodeB,
            qB.idx,
            pair_id;
            locked=true,
            assigned=true,
        )
        lockedB = query(
            qB,
            EntanglementCounterpart,
            prot.nodeA,
            qA.idx,
            pair_id;
            locked=true,
            assigned=true,
        )
        if isnothing(lockedA) || isnothing(lockedB)
            unlock(qA)
            unlock(qB)
            continue
        end

        basisA, observableA = _sixstate_basis()
        basisB, observableB = _sixstate_basis()

        # Transfer ownership from entanglement metadata to this destructive
        # consumer before measuring, mirroring EntanglementConsumer's lifecycle.
        untag!(qA, lockedA.id)
        untag!(qB, lockedB.id)

        outcomeA = Int(project_traceout!(qA, observableA))
        outcomeB = Int(project_traceout!(qB, observableB))
        bitA = outcomeA - 1
        bitB = _sixstate_canonical_bit(basisB, outcomeB)
        kept = basisA === basisB

        push!(prot._log, (
            t=now(prot.sim)::Float64,
            basisA,
            basisB,
            bitA,
            bitB,
            kept,
        ))

        @debug(
            "Measured a six-state QKD pair",
            _group=LOG_GROUPS.protocol,
            event=:sixstate_qkd_pair_measured,
            protocol_log_context(prot)...,
            slots=(qA.idx, qB.idx),
            pair_id=pair_id,
            basisA,
            basisB,
            kept,
        )

        unlock(qA)
        unlock(qB)

        if !isnothing(prot.period)
            @yield timeout(prot.sim, prot.period::Float64)
        end
    end
end
