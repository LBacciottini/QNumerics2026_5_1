using ConcurrentSim
using Distributions
using Plots
using Random
using ResumableFunctions
using Statistics

# # A repeater chain
#
# This builds on `repeater_solution.jl`.  Each node has two memories:
# one facing left and one facing right.  A memory can be empty-but-reserved while
# entanglement generation is in progress, or it can contain an entangled pair.
#
# The important difference from the two-link repeater is that an entangled pair must
# remember the remote node it is entangled with.  When a middle node swaps a left pair
# and a right pair, the remote endpoints keep their qubits, but their stored metadata
# changes: they are no longer entangled with the middle node, they are entangled with
# each other.

abstract type MemoryContent end

struct EmptyMemory <: MemoryContent end

struct EntangledPair <: MemoryContent
    remote_node::Int
end

entangled_with(pair::MemoryContent) = nothing
entangled_with(pair::EntangledPair) = pair.remote_node

mutable struct ChainNode
    left_memory::Store{MemoryContent}
    right_memory::Store{MemoryContent}
end

function ChainNode(env::Environment; memory_size=1)
    left_memory = Store{MemoryContent}(env; capacity=memory_size)
    right_memory = Store{MemoryContent}(env; capacity=memory_size)
    put!(left_memory, EmptyMemory())
    put!(right_memory, EmptyMemory())
    ChainNode(left_memory, right_memory)
end

mutable struct RepeaterChain
    nodes::Vector{ChainNode}
    num_elementary_links::Int
    completed_pairs::Int
    completion_times::Vector{Float64}
end
nodes(chain::RepeaterChain) = chain.nodes

function RepeaterChain(env::Environment, num_elementary_links::Int; memory_size=1)
    ispow2(num_elementary_links) ||
        throw(ArgumentError("num_elementary_links must be a power of two"))
    num_nodes = num_elementary_links + 1
    nodes = [ChainNode(env; memory_size) for _ in 1:num_nodes]
    RepeaterChain(nodes, num_elementary_links, 0, Float64[])
end

is_entanglement(content::MemoryContent) = false
is_entanglement(content::EntangledPair) = true
is_empty_memory(content::MemoryContent) = false
is_empty_memory(content::EmptyMemory) = true

is_entangled_with(remote_node::Int) =
    content -> entangled_with(content) == remote_node

function memory_toward(chain::RepeaterChain, node::Int, remote_node::Int)
    "Get the memory of `node` that is facing toward `remote_node`."
    remote_node < node && return nodes(chain)[node].left_memory
    remote_node > node && return nodes(chain)[node].right_memory
    throw(ArgumentError("a node cannot be entangled with itself"))
end

get_left(chain::RepeaterChain, node::Int, remote_node::Int) =
    get(nodes(chain)[node].left_memory, is_entangled_with(remote_node))

get_right(chain::RepeaterChain, node::Int, remote_node::Int) =
    get(nodes(chain)[node].right_memory, is_entangled_with(remote_node))

put_left!(chain::RepeaterChain, node::Int, content::MemoryContent) =
    put!(nodes(chain)[node].left_memory, content)

put_right!(chain::RepeaterChain, node::Int, content::MemoryContent) =
    put!(nodes(chain)[node].right_memory, content)

@resumable function entangler(
        env::Environment,
        chain::RepeaterChain,
        left_node::Int,
        success_probability::Float64,
        attempt_time::Float64,
    )
    right_node = left_node + 1
    left_memory = nodes(chain)[left_node].right_memory
    right_memory = nodes(chain)[right_node].left_memory
    attempts_until_success = Geometric(success_probability)

    while true
        ###############
        # Code here
        ###############
    end
end

@resumable function swapper(
        env::Environment,
        chain::RepeaterChain,
        node::Int,
        left_remote::Int,
        right_remote::Int,
        swap_time::Float64,
    )
    while true
        left_remote_memory = memory_toward(chain, left_remote, node)
        right_remote_memory = memory_toward(chain, right_remote, node)

        ###############
        # Code here
        ###############
    end
end

@resumable function final_pair_consumer(
        env::Environment,
        chain::RepeaterChain,
    )
    final_memory = nodes(chain)[1].right_memory
    final_remote_node = length(nodes(chain))

    while true
        final_request = get(final_memory, is_entangled_with(final_remote_node))
        @yield final_request

        far_end_memory = nodes(chain)[final_remote_node].left_memory
        @yield get(far_end_memory, is_entangled_with(1))

        chain.completed_pairs += 1
        push!(chain.completion_times, now(env))
        @yield put!(final_memory, EmptyMemory())
        @yield put!(far_end_memory, EmptyMemory())
    end
end

function start_chain_processes!(
        env::Environment,
        chain::RepeaterChain,
        success_probability::Float64,
        attempt_time::Float64,
        swap_time::Float64,
    )
    for left_node in 1:chain.num_elementary_links
        @process entangler(
            env,
            chain,
            left_node,
            success_probability,
            attempt_time,
        )
    end

    segment_length = 2
    while segment_length <= chain.num_elementary_links
        half_length = segment_length ÷ 2

        for left_endpoint in 1:segment_length:chain.num_elementary_links
            node = left_endpoint + half_length
            right_endpoint = left_endpoint + segment_length
            @process swapper(env, chain, node, left_endpoint, right_endpoint, swap_time)
        end

        segment_length *= 2
    end

    @process final_pair_consumer(env, chain)
    chain
end

function run_chain(;
        simulation_time=1_000.0,
        num_elementary_links=4,
        success_probability=1.0,
        attempt_time=1.0,
        swap_time=1.0,
        memory_size=1,
        seed=1234,
    )
    Random.seed!(seed)

    sim = Simulation()
    chain = RepeaterChain(sim, num_elementary_links; memory_size)
    start_chain_processes!(
        sim,
        chain,
        success_probability,
        attempt_time,
        swap_time,
    )

    run(sim, simulation_time)
    chain
end

function sampled_counts(completion_times, sample_times)
    counts = zeros(Int, length(sample_times))
    completed = 0

    for (i, sample_time) in pairs(sample_times)
        while completed < length(completion_times) &&
                completion_times[completed + 1] <= sample_time
            completed += 1
        end
        counts[i] = completed
    end

    counts
end

cycle_times(chain::RepeaterChain) = diff([0.0; chain.completion_times])

function plot_chain_run(chain::RepeaterChain; simulation_time=1_000.0)
    sample_times = range(0, simulation_time; length=200)
    counts = sampled_counts(chain.completion_times, sample_times)

    throughput_plot = plot(
        sample_times,
        counts;
        xlabel="Simulation time",
        ylabel="Completed end-to-end pairs",
        label=false,
        linewidth=2,
        title="Chain throughput",
    )

    cycle_plot = histogram(
        cycle_times(chain);
        xlabel="Time between end-to-end pairs",
        ylabel="Count",
        label=false,
        bins=30,
        title="Completion-time fluctuations",
    )

    plot(throughput_plot, cycle_plot; layout=(1, 2), size=(900, 350))
end

function sweep_chain_length(;
        num_elementary_links_values=(1, 2, 4, 8),
        simulation_time=1_000.0,
        success_probability=1.0,
        attempt_time=1.0,
        swap_time=1.0,
        memory_size=1,
        seed=1234,
    )
    throughputs = [
        run_chain(;
            simulation_time,
            num_elementary_links,
            success_probability,
            attempt_time,
            swap_time,
            memory_size,
            seed,
        ).completed_pairs / simulation_time
        for num_elementary_links in num_elementary_links_values
    ]

    plot(
        collect(num_elementary_links_values),
        throughputs;
        xlabel="Number of elementary links",
        ylabel="End-to-end pairs per time unit",
        label=false,
        marker=:circle,
        linewidth=2,
        title="Longer chains have lower throughput",
    )
end

simulation_time = 1_000.0
chain = run_chain(; simulation_time, num_elementary_links=4)

@assert chain.completed_pairs == length(chain.completion_times)
@assert issorted(chain.completion_times)
@assert all(diff(chain.completion_times) .> 0)

println("Completed end-to-end pairs: $(chain.completed_pairs)")
println("Mean time between pairs: $(round(mean(cycle_times(chain)), sigdigits=4))")

display(plot_chain_run(chain; simulation_time))
display(sweep_chain_length(; simulation_time))
