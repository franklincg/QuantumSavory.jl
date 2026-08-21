using Test

include(joinpath(@__DIR__, "..", "..", "examples", "diamond_failover", "setup.jl"))

@testset "dual-path diamond failover" begin
    healthy = run_diamond_scenario(
        failed_path=:none,
        duration=12.0,
        seed=138,
        success_prob=0.8,
        attempt_time=0.02,
    )
    upper_failed = run_diamond_scenario(
        failed_path=:upper,
        duration=12.0,
        seed=138,
        success_prob=0.8,
        attempt_time=0.02,
    )
    lower_failed = run_diamond_scenario(
        failed_path=:lower,
        duration=12.0,
        seed=138,
        success_prob=0.8,
        attempt_time=0.02,
    )

    @test nv(healthy.graph) == 4
    @test ne(healthy.graph) == 4
    @test healthy.deliveries > 0
    @test upper_failed.deliveries > 0
    @test lower_failed.deliveries > 0
    @test isfinite(healthy.mean_xx)
    @test isfinite(healthy.mean_zz)

    @test path_enabled((1, 2), :none)
    @test !path_enabled((1, 2), :upper)
    @test path_enabled((1, 3), :upper)
    @test !path_enabled((1, 3), :lower)
    @test_throws ArgumentError path_enabled((1, 2), :invalid)
end
