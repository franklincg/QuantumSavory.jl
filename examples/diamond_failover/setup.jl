using QuantumSavory
using QuantumSavory.ProtocolZoo
using Graphs
using ConcurrentSim
using ResumableFunctions
using NetworkLayout
using Random

const DIAMOND_EDGES = ((1, 2), (2, 4), (1, 3), (3, 4))
const UPPER_PATH_EDGES = Set(((1, 2), (2, 4)))
const LOWER_PATH_EDGES = Set(((1, 3), (3, 4)))

"""Return true when `edge` should generate entanglement in this scenario."""
function path_enabled(edge::Tuple{Int,Int}, failed_path::Symbol)
    failed_path === :none && return true
    failed_path === :upper && return !(edge in UPPER_PATH_EDGES)
    failed_path === :lower && return !(edge in LOWER_PATH_EDGES)
    throw(ArgumentError("failed_path must be :none, :upper, or :lower"))
end

"""Build a four-node diamond network with two disjoint repeater paths.

Alice is node 1 and Bob is node 4. The upper path is 1-2-4 and the lower path is
1-3-4. A failed path remains present in the topology but its link entanglers are
not started, modelling a hard link outage while preserving the routing picture.
"""
function prepare_diamond_simulation(; failed_path::Symbol=:none,
    success_prob::Float64=0.35, attempt_time::Float64=0.05,
    regsize::Int=12, consumer_period::Float64=0.05)

    graph = SimpleGraph(4)
    for (src, dst) in DIAMOND_EDGES
        add_edge!(graph, src, dst)
    end

    net = RegisterNet(graph, [Register(regsize, T2Dephasing(200.0)) for _ in 1:4])
    sim = get_time_tracker(net)

    for edge in DIAMOND_EDGES
        path_enabled(edge, failed_path) || continue
        src, dst = edge
        entangler = EntanglerProt(sim, net, src, dst;
            rounds=-1,
            randomize=true,
            success_prob,
            attempt_time,
            retry_lock_time=0.02,
        )
        @process entangler()
    end

    # Each repeater only joins pairs from Alice-facing and Bob-facing links.
    for repeater in (2, 3)
        swapper = SwapperProt(sim, net, repeater;
            nodeL=(==(1)),
            nodeH=(==(4)),
            rounds=-1,
            randomize=true,
            retry_lock_time=0.02,
        )
        @process swapper()
    end

    for node in vertices(net)
        @process EntanglementTracker(sim, net, node)()
    end

    consumer = EntanglementConsumer(sim, net, 1, 4; period=consumer_period)
    @process consumer()

    return sim, net, graph, consumer
end

"""Run a bounded deterministic scenario and return user-facing metrics."""
function run_diamond_scenario(; failed_path::Symbol=:none,
    duration::Float64=30.0, seed::Int=138, kwargs...)
    Random.seed!(seed)
    sim, net, graph, consumer = prepare_diamond_simulation(; failed_path, kwargs...)
    run(sim, duration)
    deliveries = length(consumer._log)
    mean_xx = isempty(consumer._log) ? NaN : sum(entry.obs1 for entry in consumer._log) / deliveries
    mean_zz = isempty(consumer._log) ? NaN : sum(entry.obs2 for entry in consumer._log) / deliveries
    return (; sim, net, graph, consumer, deliveries, mean_xx, mean_zz)
end
