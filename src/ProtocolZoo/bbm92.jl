using Random: rand

export BBM92Prot, bbm92_log, sifted_key

"""
$TYPEDEF

Entanglement-based BBM92 quantum-key-distribution protocol.

`BBM92Prot` consumes Bell pairs shared by `nodeA` and `nodeB`. For each pair,
each endpoint independently chooses the X or Z basis, measures its qubit, and
records whether the round survives basis sifting. With ideal `|Φ⁺⟩` pairs,
same-basis rounds produce matching raw key bits.

The protocol intentionally models the quantum measurement and basis-sifting
primitive only. Error correction, privacy amplification, authentication, and a
network attacker model are higher-layer concerns.

$FIELDS
"""
@kwdef struct BBM92Prot <: AbstractProtocol
    """time-and-schedule-tracking instance from `ConcurrentSim`"""
    sim::Simulation
    """a network graph of registers"""
    net::RegisterNet
    """the vertex index of Alice's node"""
    nodeA::Int
    """the vertex index of Bob's node"""
    nodeB::Int
    """probability of choosing the Z basis independently at each endpoint"""
    z_basis_probability::Float64 = 0.5
    """delay between unsuccessful pair queries and after each measured pair (`nothing` waits on tag changes when idle)"""
    period::Union{Float64,Nothing} = 0.1
    """measurement records; the concrete storage type is private"""
    _log::Vector{@NamedTuple{t::Float64,basisA::Symbol,basisB::Symbol,bitA::Int,bitB::Int,kept::Bool}} =
        @NamedTuple{t::Float64,basisA::Symbol,basisB::Symbol,bitA::Int,bitB::Int,kept::Bool}[]
end

function BBM92Prot(sim::Simulation, net::RegisterNet, nodeA::Int, nodeB::Int; kwargs...)
    zprob = get(kwargs, :z_basis_probability, 0.5)
    0.0 <= zprob <= 1.0 || throw(ArgumentError("z_basis_probability must be in [0, 1]"))
    period = get(kwargs, :period, 0.1)
    (isnothing(period) || period > 0) || throw(ArgumentError("period must be positive or nothing"))
    return BBM92Prot(; sim, net, nodeA, nodeB, kwargs...)
end

function BBM92Prot(net::RegisterNet, nodeA::Int, nodeB::Int; kwargs...)
    return BBM92Prot(get_time_tracker(net), net, nodeA, nodeB; kwargs...)
end

permits_virtual_edge(::Type{BBM92Prot}) = true
_protocol_nodes(prot::BBM92Prot) = (prot.nodeA, prot.nodeB)

protocol_catalog_metadata(::Type{BBM92Prot}) = (
    attachment=:edge,
    attachment_fields=(node_a=:nodeA, node_b=:nodeB),
    required_fields=(),
)

"""Return a copy of the BBM92 measurement/sifting records."""
bbm92_log(prot::BBM92Prot) = copy(prot._log)

"""Return Alice's sifted raw key bits from same-basis BBM92 rounds."""
sifted_key(prot::BBM92Prot) = [entry.bitA for entry in prot._log if entry.kept]

_bbm92_basis(probability::Float64) = rand() < probability ? (:Z, Z) : (:X, X)

@resumable function (prot::BBM92Prot)()
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

        # Every yield can invalidate a query. Revalidate both reciprocal tags and
        # the pair identifier while holding the slots before destructive measurement.
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

        basisA, observableA = _bbm92_basis(prot.z_basis_probability)
        basisB, observableB = _bbm92_basis(prot.z_basis_probability)

        # Remove the durable counterpart metadata before consuming the pair. This
        # mirrors EntanglementConsumer's ownership transition: after measurement
        # no peer may discover this pair as live entanglement.
        untag!(qA, lockedA.id)
        untag!(qB, lockedB.id)

        bitA = Int(project_traceout!(qA, observableA)) - 1
        bitB = Int(project_traceout!(qB, observableB)) - 1
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
            "Measured a BBM92 pair",
            _group=LOG_GROUPS.protocol,
            event=:bbm92_pair_measured,
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
