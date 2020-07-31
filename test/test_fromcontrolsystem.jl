include("../src/abstraction.jl")

module TestMain

using Test
using Main.Abstraction
AB = Main.Abstraction

sleep(0.1) # used for good printing
println("Started test")

@testset "FromControlSystem" begin
lb = (0.0, 0.0)
ub = (10.0, 11.0)
x0 = (0.0, 0.0)
h = (1.0, 2.0)
X_grid = AB.NewGridSpaceHash(x0, h)
AB.add_to_gridspace!(X_grid, AB.HyperRectangle(lb, ub), AB.OUTER)
X_full = AB.NewSubSet(X_grid)
AB.add_to_subset_all!(X_full)

lb = (-1.0,)
ub = (1.0,)
u0 = (0.0,)
h = (0.5,)
U_grid = AB.NewGridSpaceHash(u0, h)
AB.add_to_gridspace!(U_grid, AB.HyperRectangle(lb, ub), AB.OUTER)

tstep = 5.0
n_sys = 3
n_bound = 3
# F_sys(x, u) = [1.0-cos(x[2]), -x[1] + u[1]]
# L_bound(u) = [0.0 1.0; 1.0 0.0]
F_sys(x, u) = (u[1], -cos(x[1]))
L_bound(r, u) = (0.0, r[1])
sys_noise = (1.0, 1.0).*0.1
meas_noise = (1.0, 1.0).*0.0

cont_sys = AB.NewControlSystemRK4(tstep, F_sys, L_bound, sys_noise, meas_noise, n_sys, n_bound)
sym_model = sym_model = AB.NewSymbolicModelHash(X_grid, U_grid, X_grid)
AB.set_symmodel_from_controlsystem!(sym_model, cont_sys)
@test length(sym_model.elems) == 1145

x_pos = (1, 2)
u_pos = (1,)
x = AB.get_coords_by_pos(X_grid, x_pos)
u = AB.get_coords_by_pos(U_grid, u_pos)
x_ref = AB.get_ref_by_pos(X_grid, x_pos)
u_ref = AB.get_ref_by_pos(U_grid, u_pos)

X_simple = AB.NewSubSet(X_grid)
AB.add_to_subset_by_pos!(X_simple, x_pos)
U_simple = AB.NewSubSet(U_grid)
AB.add_to_subset_by_pos!(U_simple, u_pos)
Y_simple = AB.NewSubSet(X_grid)
yref_coll = AB.get_gridspace_reftype(X_grid)[]
AB.add_images_by_xref_uref!(yref_coll, sym_model, x_ref, u_ref)
AB.add_to_subset_by_ref_coll!(Y_simple, yref_coll)
display(Y_simple)

@static if get(ENV, "TRAVIS", "false") == "false"
    include("../src/plotting.jl")
    using PyPlot
    fig = PyPlot.figure()
    ax = fig.gca()
    ax.set_xlim([-1.0, 11.0])
    ax.set_ylim([-2.0, 14.0])
    Plot.subset!(ax, 1:2, X_full, fa = 0.1)
    Plot.subset!(ax, 1:2, X_simple)
    Plot.subset!(ax, 1:2, Y_simple)
    Plot.trajectory_open_loop!(ax, 1:2, cont_sys, x, u, 50)
    Plot.cell_image!(ax, 1:2, X_simple, U_simple, cont_sys)
    Plot.cell_approx!(ax, 1:2, X_simple, U_simple, cont_sys)
end
end

sleep(0.1) # used for good printing
println("End test")

end  # module TestMain