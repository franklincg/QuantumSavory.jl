using Test
using Random
using Graphs
using ConcurrentSim
using ResumableFunctions
using QuantumSavory
using QuantumSavory.ProtocolZoo

function direct_qkd_sim(; slots=16)
    graph = SimpleGraph(2)
    add_edge!(graph, 1, 2)
    net = RegisterNet(graph, [Register(slots), Register(slots)])
    sim = get_time_tracker(net)

    entangler = EntanglerProt(
        sim, net, 1, 2;
        rounds=-1,
        success_prob=1.0,
        attempt_time=0.01,
        retry_lock_time=0.01,
        randomize=true,
    )
    @process entangler()

    qkd = SixStateQKDProt(sim, net, 1, 2; period=0.01)
    @process qkd()
    return sim, net, qkd
end

@testset "six-state QKD direct link" begin
    Random.seed!(137)
    sim, net, qkd = direct_qkd_sim()
    run(sim, 3.0)

    records = sixstate_log(qkd)
    kept = [record for record in records if record.kept]

    @test length(records) >= 9
    @test length(kept) >= 3
    @test all(record.basisA in (:X, :Y, :Z) for record in records)
    @test all(record.basisB in (:X, :Y, :Z) for record in records)
    @test all(record.kept == (record.basisA === record.basisB) for record in records)
    @test all(record.bitA == record.bitB for record in kept)
    @test length(sifted_key(qkd)) == length(kept)
    @test qber_estimate(qkd) == 0.0
    @test permits_virtual_edge(SixStateQKDProt)
    @test protocol_log_context(qkd).nodes == (1, 2)
    @test_throws ArgumentError SixStateQKDProt(sim, net, 1, 2; period=0.0)
end

@testset "six-state QKD after entanglement swapping" begin
    Random.seed!(138)

    graph = path_graph(3)
    net = RegisterNet(graph, [Register(20), Register(20), Register(20)])
    sim = get_time_tracker(net)

    ent12 = EntanglerProt(
        sim, net, 1, 2;
        rounds=-1,
        success_prob=1.0,
        attempt_time=0.01,
        retry_lock_time=0.01,
        randomize=true,
    )
    ent23 = EntanglerProt(
        sim, net, 2, 3;
        rounds=-1,
        success_prob=1.0,
        attempt_time=0.01,
        retry_lock_time=0.01,
        randomize=true,
    )
    @process ent12()
    @process ent23()

    swapper = SwapperProt(
        sim, net, 2;
        nodeL=(==(1)),
        nodeH=(==(3)),
        chooseL=(_ -> 1),
        chooseH=(_ -> 1),
        rounds=-1,
        retry_lock_time=0.01,
    )
    @process swapper()

    for node in 1:3
        tracker = EntanglementTracker(sim, net, node)
        @process tracker()
    end

    qkd = SixStateQKDProt(sim, net, 1, 3; period=0.01)
    @process qkd()
    run(sim, 5.0)

    records = sixstate_log(qkd)
    kept = [record for record in records if record.kept]
    @test !isempty(records)
    @test !isempty(kept)
    @test all(record.bitA == record.bitB for record in kept)
    @test qber_estimate(qkd) == 0.0
end
