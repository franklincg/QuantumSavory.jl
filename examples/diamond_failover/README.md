# Dual-path diamond failover

This example compares end-to-end entanglement delivery across a four-node diamond network with two disjoint repeater paths between Alice (node 1) and Bob (node 4):

- upper path: `1 -> 2 -> 4`
- lower path: `1 -> 3 -> 4`

The topology remains fixed while either path can be disabled to model a hard link outage. The remaining path continues to generate, swap, track, and consume end-to-end Bell pairs.

## Run the deterministic simulation

```julia
include("setup.jl")

healthy = run_diamond_scenario(failed_path=:none)
upper_failed = run_diamond_scenario(failed_path=:upper)
lower_failed = run_diamond_scenario(failed_path=:lower)

@show healthy.deliveries
@show upper_failed.deliveries
@show lower_failed.deliveries
```

`run_diamond_scenario` records the RNG seed, uses a bounded simulation duration, and returns the delivered-pair count plus mean XX/ZZ observables measured by the standard `EntanglementConsumer`.

## Run the interactive visualization

From the top-level examples environment:

```sh
julia --project=examples examples/diamond_failover/1_interactive_visualization.jl
```

Use the controls to select a failed path, link-generation success probability, and simulation duration. Press **Run scenario** to rebuild the simulation and compare delivery counts for the healthy, upper-failed, and lower-failed cases under the same RNG seed.

## What this demonstrates

The example is intentionally small enough to inspect visually while still exercising a real multipath network. It demonstrates that end-to-end service does not depend on one unique repeater path: removing all generation on one branch leaves the other branch available for entanglement swapping and delivery.

The failed path is kept in the graph so the visualization distinguishes *topological availability* from *operational link availability*. This makes it useful for experimenting with failover, path diversity, and degraded link-generation rates without changing the network drawing itself.
