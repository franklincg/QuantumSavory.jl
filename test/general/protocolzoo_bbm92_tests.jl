using Test
using Random
using Graphs
using ConcurrentSim
using ResumableFunctions
using QuantumSavory
using QuantumSavory.ProtocolZoo

@testset "BBM92 protocol" begin
    Random.seed!(137)

    graph = SimpleGraph(2)
    add_edge!(graph, 1, 2)
    net = RegisterNet(graph, [Register(8), Register(8)])
    sim = get_time_tracker(net)

    entangler = EntanglerProt(
        sim,
        net,
        1,
        2;
        rounds=-1,
        success_prob=1.0,
        attempt_time=0.01,
        retry_lock_time=0.01,
    )
    @process entangler()

    # Force both endpoints to Z so every completed round is sifted and the ideal
    # Bell pair must yield identical raw bits.
    qkd = BBM92Prot(sim, net, 1, 2; z_basis_probability=1.0, period=0.01)
    @process qkd()

    run(sim, 2.0)

    records = bbm92_log(qkd)
    @test !isempty(records)
    @test all(record.basisA === :Z && record.basisB === :Z for record in records)
    @test all(record.kept for record in records)
    @test all(record.bitA == record.bitB for record in records)
    @test length(sifted_key(qkd)) == length(records)
    @test all(bit in (0, 1) for bit in sifted_key(qkd))
    @test permits_virtual_edge(BBM92Prot)
    @test protocol_log_context(qkd).nodes == (1, 2)

    @test_throws ArgumentError BBM92Prot(sim, net, 1, 2; z_basis_probability=-0.1)
    @test_throws ArgumentError BBM92Prot(sim, net, 1, 2; z_basis_probability=1.1)
    @test_throws ArgumentError BBM92Prot(sim, net, 1, 2; period=0.0)
end

@testset "BBM92 basis sifting" begin
    Random.seed!(138)

    graph = SimpleGraph(2)
    add_edge!(graph, 1, 2)
    net = RegisterNet(graph, [Register(12), Register(12)])
    sim = get_time_tracker(net)

    @process EntanglerProt(
        sim,
        net,
        1,
        2;
        rounds=-1,
        success_prob=1.0,
        attempt_time=0.01,
        retry_lock_time=0.01,
    )()

    qkd = BBM92Prot(sim, net, 1, 2; z_basis_probability=0.5, period=0.01)
    @process qkd()
    run(sim, 3.0)

    records = bbm92_log(qkd)
    @test length(records) >= 4
    @test any(record.kept for record in records)
    @test all(record.kept == (record.basisA === record.basisB) for record in records)
    @test all(record.bitA == record.bitB for record in records if record.kept)
end
