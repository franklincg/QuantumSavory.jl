using GLMakie

include(joinpath(@__DIR__, "setup.jl"))

failed_path = Observable(:none)
success_prob = Observable(0.35)
duration = Observable(30.0)

scenario = Observable(run_diamond_scenario(
    failed_path=failed_path[], success_prob=success_prob[], duration=duration[]))

fig = Figure(; size=(1200, 760))
Label(fig[0, 1:2], "Dual-path diamond network failover", fontsize=26)

# Network panel. A fresh scenario is rendered whenever the controls are applied.
network_slot = GridLayout()
fig[1:3, 1] = network_slot

metrics_text = Observable("")
Label(fig[1, 2], metrics_text; tellwidth=false, halign=:left, valign=:top)

ax_pairs = Axis(fig[2, 2]; xlabel="Scenario", ylabel="Delivered pairs")
scenario_names = ["healthy", "upper failed", "lower failed"]
scenario_counts = Observable([0, 0, 0])
barplot!(ax_pairs, 1:3, scenario_counts)
ax_pairs.xticks = (1:3, scenario_names)

ax_fidelity = Axis(fig[3, 2]; xlabel="Observable", ylabel="Mean value", limits=(nothing, (-1.05, 1.05)))
fid_values = Observable([0.0, 0.0])
barplot!(ax_fidelity, 1:2, fid_values)
ax_fidelity.xticks = (1:2, ["XX", "ZZ"])

controls = GridLayout()
fig[4, 1:2] = controls
menu = Menu(controls[1, 1]; options=["none" => :none, "upper path" => :upper, "lower path" => :lower], default="none")
Label(controls[1, 2], "failed path")
prob_slider = Slider(controls[2, 1]; range=0.05:0.05:1.0, startvalue=success_prob[])
Label(controls[2, 2], @lift("link success probability = $(round($prob_slider.value; digits=2))"))
duration_slider = Slider(controls[3, 1]; range=5.0:5.0:100.0, startvalue=duration[])
Label(controls[3, 2], @lift("simulation duration = $(Int($duration_slider.value))"))
apply_button = Button(controls[4, 1:2]; label="Run scenario")

function render_network!(result)
    empty!(network_slot)
    coords = Dict(1 => Point2f(0, 0), 2 => Point2f(1, 1), 3 => Point2f(1, -1), 4 => Point2f(2, 0))
    registernetplot_axis(network_slot[1, 1], result.net; registercoords=coords)
    return nothing
end

function refresh_metrics!(result)
    metrics_text[] = "Scenario: $(failed_path[])\nDelivered end-to-end pairs: $(result.deliveries)\nMean XX: $(round(result.mean_xx; digits=3))\nMean ZZ: $(round(result.mean_zz; digits=3))"
    fid_values[] = [isnan(result.mean_xx) ? 0.0 : result.mean_xx,
                    isnan(result.mean_zz) ? 0.0 : result.mean_zz]
    notify(fid_values)
end

function refresh_comparison!()
    scenario_counts[] = [
        run_diamond_scenario(failed_path=:none, success_prob=success_prob[], duration=duration[], seed=138).deliveries,
        run_diamond_scenario(failed_path=:upper, success_prob=success_prob[], duration=duration[], seed=138).deliveries,
        run_diamond_scenario(failed_path=:lower, success_prob=success_prob[], duration=duration[], seed=138).deliveries,
    ]
    notify(scenario_counts)
end

on(apply_button.clicks) do _
    failed_path[] = menu.selection[]
    success_prob[] = prob_slider.value[]
    duration[] = duration_slider.value[]
    scenario[] = run_diamond_scenario(
        failed_path=failed_path[], success_prob=success_prob[], duration=duration[], seed=138)
    render_network!(scenario[])
    refresh_metrics!(scenario[])
    refresh_comparison!()
end

render_network!(scenario[])
refresh_metrics!(scenario[])
refresh_comparison!()

display(fig)
