using session_5_1
using Test

@testset "session_5_1.jl" begin
    include("../repeater_solution.jl")

    station = run_repeater(;
        simulation_time=200.0,
        left_success_probability=0.2,
        right_success_probability=0.2,
        seed=42,
    )

    @test station.completed_pairs == length(station.completion_times)
    @test station.completed_pairs == length(station.cycle_times)
    @test station.completed_pairs > 0
    @test issorted(station.completion_times)
    @test all(diff(station.completion_times) .> 0)
    @test all(station.left_waits .>= 0)
    @test all(station.right_waits .>= 0)

    @test sampled_counts([2.0, 4.0, 8.0], [0.0, 2.0, 5.0, 10.0]) == [0, 1, 2, 3]

    slow_station = run_repeater(;
        simulation_time=200.0,
        left_success_probability=0.1,
        right_success_probability=0.1,
        seed=42,
    )
    fast_station = run_repeater(;
        simulation_time=200.0,
        left_success_probability=1.0,
        right_success_probability=1.0,
        seed=42,
    )

    @test fast_station.completed_pairs > slow_station.completed_pairs
end
