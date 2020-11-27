include("../examples/gol_lazar_belta.jl")
include("solvers.jl")
using LinearAlgebra, Test
import CDDLib
using Dionysos

_name(o::MOI.OptimizerWithAttributes) = split(string(o.optimizer_constructor), ".")[2]

@testset "Gol-Lazar-Belta" begin
    function _prob( N, q0, x0, zero_cost::Bool)
        system = gol_lazar_belta(CDDLib.Library())
        if zero_cost
            state_cost = Fill(ZeroFunction(), nmodes(system))
        else
            state_cost = [mode == system.ext[:q_T] ? ConstantFunction(0.0) : ConstantFunction(1.0)
                          for mode in modes(system)]
        end
        return OptimalControlProblem(
            system,
            q0, x0,
            Fill(state_cost, N),
            Fill(Fill(QuadraticControlFunction(ones(1, 1)), ntransitions(system)), N),
            system.ext[:q_T],
            N
        )
    end
    function _test(algo, N, q0, x0, x_expected, u_expected, obj_expected, zero_cost::Bool, mi::Bool; kws...)
        problem = _prob(N, q0, x0, zero_cost)
        @info("Solving... depth: $N")
        optimizer = MOI.instantiate(algo)
        MOI.set(optimizer, MOI.RawParameter("problem"), problem)
        @info("Solving... depth: $N")
        @time MOI.optimize!(optimizer)
        @info("Solved.")
        if x_expected === nothing
            @test MOI.get(optimizer, MOI.TerminationStatus()) == MOI.INFEASIBLE
        else
            @test MOI.get(optimizer, MOI.TerminationStatus()) == MOI.OPTIMAL
            xu = MOI.get(optimizer, ContinuousTrajectoryAttribute())
            @test typeof(x_expected) == typeof(xu.x)
            @test typeof(u_expected) == typeof(xu.u)
            if isempty(x_expected)
                @test isempty(u_expected)
                @test isempty(xu.x)
                @test isempty(xu.u)
            else
                @test xu.x ≈ x_expected atol=1e-2
                @test xu.u ≈ u_expected atol=1e-2
            end
            @test MOI.get(optimizer, MOI.ObjectiveValue()) ≈ obj_expected atol=1e-2
        end
        x_expected !== nothing && optimizer isa BranchAndBound.Optimizer && return optimizer.Q_function
        return
    end
    function learn_test(qp_solver, x0 = [-1.645833614657878, 1.7916672467705592])
        prob = _prob(1, 15, x0, false)
        t(i, j) = first(transitions(prob.system, i, j))
        dtraj = Dionysos.DiscreteTrajectory(15, [t(15, 20)])
        ctraj = Dionysos.ContinuousTrajectory(
            [[-0.5, 0.5]],
            [[-1.2916666674915085]]
        )
        algo = HybridDualDynamicProgrammingAlgo(qp_solver, 1e-5)
        Q_function = Dionysos.instantiate(prob, algo)
        Dionysos.learn(Q_function, prob, dtraj, ctraj, algo)
        @test isempty(Q_function.cuts[0, 15])
        @test !hasallhalfspaces(Q_function.domains[0, 15])
        @test length(Q_function.cuts[1, 15]) == 1
        @test first(Q_function.cuts[1, 15]) ≈ Dionysos.AffineFunction([0.0, 2.583334480953581], -2.960071516682004) rtol=1e-6
        @test !hashyperplanes(Q_function.domains[1, 15]) == 1
        @test nhalfspaces(Q_function.domains[1, 15]) == 1
        a = normalize([2, 1])
        @test first(halfspaces(Q_function.domains[1, 15])) ≈ HalfSpace(a, -a ⋅ x0)
        @test isempty(Q_function.cuts[0, 20])
        @test !hasallhalfspaces(Q_function.domains[0, 20])
        @test isempty(Q_function.cuts[1, 20])
        @test !hasallhalfspaces(Q_function.domains[1, 20])
    end
    function _test9(algo; kws...)
        _test(algo, 9, 8, [1.5, -2.5],
              x_expected_9,
              u_expected_9,
              11.71875, false, true; kws...)
    end
    function _test11(algo; kws...)
        _test(algo, 11, 3, [1.0, -6.0],
              x_expected_11,
              u_expected_11,
              21.385062979189478, false, true; kws...)
    end
    x_expected_9 = [
        [-0.925 , -2.35],
        [-3.0625, -1.925],
        [-4.6375, -1.225],
        [-5.375 , -0.25],
        [-5.0   ,  1.0],
        [-3.8375,  1.325],
        [-2.5   ,  1.35],
        [-1.2875,  1.075],
        [-0.5   ,  0.5]]
    u_expected_9 = [[0.15], [0.425], [0.7], [0.975], [1.25], [0.325], [0.025], [-0.275], [-0.575]]
    x_expected_11 = [
        [-4.02204,  -4.04409],
        [-7.23015,  -2.37212],
        [-8.90827,  -0.984118],
        [-9.34036,   0.119934],
        [-8.81038,   0.940033],
        [-7.60227,   1.47618],
        [-6.0    ,   1.72837],
        [-4.26869,   1.73426],
        [-2.63582,   1.53149],
        [-1.31004,   1.12007],
        [-0.5    ,   0.5]]
    u_expected_11 = [
        [ 1.9559145673603502],
        [ 1.6719605695509308],
        [ 1.3880065717415113],
        [ 1.1040525739320919],
        [ 0.8200985761226725],
        [ 0.5361445783132529],
        [ 0.2521905805038335],
        [ 0.0058871851040525],
        [-0.2027656078860899],
        [-0.4114184008762322],
        [-0.6200711938663745]]
    function tests(qp_solver, miqp_solver)
        # Pavito does not support indicator constraints yet so we use `false` here
        @testset "$(_name(algo))" for algo in [
            optimizer_with_attributes(BemporadMorari.Optimizer, "continuous_solver" => qp_solver, "mixed_integer_solver" => miqp_solver,
                                     "indicator" => false, "log_level" => 0),
            optimizer_with_attributes(BranchAndBound.Optimizer, "continuous_solver" => qp_solver, "mixed_integer_solver" => miqp_solver,
                                     "max_iter" => 1111)
#            BranchAndBound(qp_solver, miqp_solver, HybridDualDynamicProgrammingAlgo(qp_solver), max_iter = 871)
        ]
            @testset "Depth: 0" begin
            _test(algo, 0, 18, [0.0, 1.0], nothing, nothing, nothing, true, false)
            _test(algo, 0, 20, [0.5, 0.0], Vector{Float64}[], Vector{Float64}[], 0.0, true, false)
            end
            @testset "Depth: 1" begin
            _test(algo, 1, 18, [0.0, 1.0], [[0.5, 0.0]], [[-1.0]], 1.0, true, false)
            _test(algo, 1, 7, [0.0, 1.0], nothing, nothing, nothing, true, false)
            end
            @testset "Depth: 2" begin
            _test(algo, 2, 18, [0.0, 1.0], [[0.55, 0.1], [0.5, -0.2]], [[-0.9], [-0.3]], 0.9, true, true)
            _test(algo, 2, 7, [0.0, 1.0], nothing, nothing, nothing, true, true)
            end
            @testset "Depth: 9" begin
                _test9(algo)
            end
            @testset "Depth: 11" begin
                _test11(algo)
            end
        end
    end
    function test_Q_reuse(qp_solver, miqp_solver)
        # Pavito does not support indicator constraints yet so we use `false` here

        algo(max_iter, Q_function_init) = optimizer_with_attributes(
            BranchAndBound.Optimizer, "continuous_solver" => qp_solver, "mixed_integer_solver" => miqp_solver,
            "max_iter" => max_iter, "Q_function_init" => Q_function_init)
        qalgo(max_iter) = optimizer_with_attributes(
            BranchAndBound.Optimizer, "continuous_solver" => qp_solver, "mixed_integer_solver" => miqp_solver,
            "max_iter" => max_iter, "lower_bound" => HybridDualDynamicProgrammingAlgo(qp_solver, 1e-5))
        Q9 = _test9(qalgo(990))    # 871 | 976--987
        @show sum(length.(Q9.cuts))
        _test9(algo(960, Q9))      # 761 | 940--954
        _test11(algo(96, Q9))      #  85 | 95,96
        Q11 = _test11(qalgo(96))   #  85 | 96
        @show sum(length.(Q11.cuts))
        _test9(algo(1011, Q11))    # 880 | 1011
        _test11(algo(96, Q11))     #  85 | 96
        Q = Dionysos.q_merge(Q9, Q11)
        _test9(algo(950, Q))       # 747 | 928,944
        _test11(algo(96, Q))       #  85 | 95,96
    end
    tests(qp_solver, miqp_solver)
    @testset "Q_reuse" begin
        test_Q_reuse(qp_solver, miqp_solver)
    end
    @testset "Learn test" begin
        learn_test(qp_solver)
    end
end
