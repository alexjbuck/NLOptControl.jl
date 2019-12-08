module Base

using JuMP
using DataFrames
using Interpolations
using CSV
using Printf

# These functions are required for MPC_Module.jl and PrettyPlots.jl (resultsDir!)
export
  evalConstraints!,
  opt2dfs!,
  dvs2dfs,
  plant2dfs!,
  postProcess!,
  optimize!,
  scale_tau,
  try_import,
  intervals,
  interpolateLagrange!,
  interpolateLinear!,
  interpolate_lagrange,
  State,
  Control,
  Constraint,
  Results,
  Settings,
  _Ipopt_defaults,
  _Ipopt_MPC,
  # _KNITRO_defaults,
  # _KNITRO_MPC,
  simulationModes,
  resultsDir!

################################################################################
# Constants
################################################################################
#####################################
# settings for both KNITRO and IPOPT
####################################
#outlev # (c.m.solver==:Ipopt) ? :print_level : :outlev # print level
# (KNITRO) absolute stopping tolerance for the feasibility error
# (Ipopt) Absolute tolerance on the constraint violation.
#feastol_abs # (c.m.solver==:Ipopt) ? :constr_viol_tol : :feastol_abs
# (KNITRO) maximum number of iterations before termination
# (Ipopt) Maximum number of iterations.
#maxit # (c.m.solver==:Ipopt) ? :max_iter : :maxit
# (KNITRO) in seconds, the maximum allowable CPU time before termination
# (Ipopt) A limit on CPU seconds that Ipopt can use to solve one problem
#maxtime_cpu # (c.m.solver==:Ipopt) ? :max_cpu_time : :maxtime_cpu
const _Ipopt_defaults=Dict(
  :print_level                =>0,
  :warm_start_init_point      =>"yes",
  :tol                        =>1e-8,
  :max_iter                   =>3000,
  :max_cpu_time               =>1e6,
  :dual_inf_tol               =>1.,
  :constr_viol_tol            =>0.0001,
  :compl_inf_tol              =>0.0001,
  :acceptable_tol             =>1e-6,
  :acceptable_constr_viol_tol =>0.01,
  :acceptable_dual_inf_tol    =>1e-10,
  :acceptable_compl_inf_tol   =>0.01,
  :acceptable_obj_change_tol  =>1e20,
  :diverging_iterates_tol     =>1e20
)

const _Ipopt_MPC=Dict(
  :print_level                =>0,
  :warm_start_init_point      =>"yes",
  :tol                        =>5e-1,
  :max_iter                   =>500,
  :max_cpu_time               =>0.47,
  :dual_inf_tol               =>5.,
  :constr_viol_tol            =>1e-1,
  :compl_inf_tol              =>1e-1,
  :acceptable_tol             =>1e-2,
  :acceptable_constr_viol_tol =>0.01,
  :acceptable_dual_inf_tol    =>1e10,
  :acceptable_compl_inf_tol   =>0.01,
  :acceptable_obj_change_tol  =>1e20,
  :diverging_iterates_tol     =>1e20
)

# const _KNITRO_defaults=Dict(
#  :outlev                       =>1,
#  :feastol                      =>1.0e-6,
#  :feastol_abs                  =>1e-3,
#  :ftol                         =>1e-15,
#  :ftol_iters                   =>5,
#  :infeastol                    =>1.0e-8,
#  :maxfevals                    =>-1,
#  :maxit                        =>0,
#  :maxtime_cpu                  =>1e8,
#  :maxtime_real                 =>1e8,
#  :opttol                       =>1e-6,
#  :opttol_abs                   =>1e-3,
#  :xtol                         =>1e-12,
#  :xtol_iters                   =>0,
#  :algorithm                    =>0,
#  :bar_initpt                   =>0,
#  :bar_murule                   =>0,
#  :bar_penaltycons              =>0,
#  :bar_penaltyrule              =>0,
#  :bar_switchrule               =>0,
#  :linesearch                   =>0,
#  :linsolver                    =>0,
#  :cg_pmem                      =>10,
#  :bar_initpt                   =>0,
#  :bar_penaltycons              =>0,
#  :bar_penaltyrule              =>0,
#  :bar_switchrule               =>0,
#  :linesearch                   =>0,
#  :tuner                        =>0
# )
#
# const _KNITRO_MPC=Dict(
#  :outlev                       =>0,
#  :feastol                      =>1.0e20,
#  :feastol_abs                  =>7e-2,
#  :ftol                         =>1e-15,
#  :ftol_iters                   =>5,
#  :infeastol                    =>1e-2,
#  :maxfevals                    =>-1,
#  :maxit                        =>0,
#  :maxtime_cpu                  =>1e8,
#  :maxtime_real                 =>0.47,
#  :opttol                       =>1.0e20,
#  :opttol_abs                   =>5e-1,
#  :xtol                         =>1e-12,
#  :xtol_iters                   =>0,
#  :algorithm                    =>1,
#  :bar_initpt                   =>0,
#  :bar_murule                   =>1,
#  :bar_penaltycons              =>0,
#  :bar_penaltyrule              =>0,
#  :bar_switchrule               =>0,
#  :linesearch                   =>0,
#  :linsolver                    =>4,
#  :cg_pmem                      =>0,
#  :bar_initpt                   => 3,
#  :bar_penaltycons              => 1,
#  :bar_penaltyrule              => 2,
#  :bar_switchrule               => 2,
#  :linesearch                   => 1,
#  :tuner                        =>0
# )

const simulationModes = [:OCP,:IP,:IPEP,:EP]

################################################################################
# structs
################################################################################
############################### control ########################################
mutable struct Control
  name::Vector{Any}
  description::Vector{Any}
  num::Int64
  pts::Int64
end
function Control()
  Control([],
          [],
          0,
          0)
end
# ############################# state  ##########################################
mutable struct State
  name::Vector{Any}
  description::Vector{Any}
  num::Int64
  pts::Int64
  model
end
function State()
  State([],
        [],
        0,
        0,
        Any)
end

############################## constraint ######################################
mutable struct Constraint
  name::Vector{Any}
  handle::Vector{Any}
  value::Vector{Any}
  nums  # range of indecies in g(x)
end
function Constraint()
  Constraint([],
             [],
             [],
             []);
end

############################### solver  ########################################
mutable struct Solver
    name
    settings
end

function Solver()
       Solver(:Ipopt,
              _Ipopt_defaults);
end

mutable struct PlantResults
  plant
  X0p
  X0a  # closest one in time to X0e
  X0e
  e
  dfsplant
  dfsplantPts::DataFrames.DataFrame # plant data extracted into a single DataFrame
  dfsX0p
  dfsX0a
  dfsX0e
  dfse
end

function PlantResults()
 PlantResults(
    DataFrame(), # plantdata
  Vector{Any}[],
  Vector{Any}[],
  Vector{Any}[],
  Matrix{Any}[], # e
           [],   # vector of plantdata dfs
  DataFrame(),
  DataFrame(),
  DataFrame(),
  DataFrame(),
  DataFrame()
      )
end

mutable struct OCPResults
  tctr                       # time vector for control
  tst                        # time vector for state
  x                          # JuMP states
  u                          # JuMP controls
  X                          # states
  U                          # controls
  X0                         # initial states for OCP
  CS                         # costates
  tpolyPts                   # time sample points for polynomials  (NOTE these interpolated solutions were developed for calulaing error, between them and a known Optimal solution)
  XpolyPts                   # state evaluated using Lagrange/Linear polynomial
  CSpolyPts                  # costate evaluated using Lagrange/Linear polynomial
  UpolyPts                   # control evaluated using Lagrane/Linear polynomial
  AlltpolyPts                   # time sample points for polynomials
  AllXpolyPts                   # state evaluated using Lagrange/Linear polynomial
  AllCSpolyPts                  # costate evaluated using Lagrange/Linear polynomial
  AllUpolyPts                   # control evaluated using Lagrane/Linear polynomial
  tpts                       # vector time sample points
  Xpts                       # vector state sample points
  Upts                       # vector control sample points
  CSpts                      # vector costate sample points
  x0Con                      # handle for initial state constraints
  x0sCon
  xfCon                      # handle for final state constraints
  xfsCon
  dynCon                     # dynamics constraints
  constraint::Constraint     # constraint handles and data
  evalNum                    # number of times optimization has been run
  iterNum                    # mics. data, perhaps an iteration number for a higher level algorithm
  status                     # optimization status
  tSolve                     # solve time for optimization
  objVal                     # objective function value
  dfs                        # results in DataFrame for plotting
  dfsOpt                     # optimization information in DataFrame for plotting
  dfsCon                     # constraint data
end

# Default Constructor
function OCPResults()
OCPResults( Vector{Any}[],# time vector for control
        Vector{Any}[],    # time vector for state
        Matrix{Any}[],    # JuMP states
        Matrix{Any}[],    # JuMP controls
        Matrix{Any}[],    # states
        Matrix{Any}[],    # controls
        Vector{Any}[],    # initial states for OCP
        [],               # costates
        [],               # time sample points for polynomials
        [],               # state evaluated using Lagrange polynomial
        [],               # costate evaluated using Lagrange polynomial
        [],               # control evaluated using Lagrange polynomial
        [],
        [],
        [],
        [],
        Vector{Any}[],    # vector time sample points
        Vector{Any}[],    # vector state sample points
        Vector{Any}[],    # vector control sample points
        Vector{Any}[],    # vector costate sample points
        nothing,          # handle for initial state constraints
        nothing,
        nothing,          # handle for final state constraints
        nothing,
        nothing,          # dynamics constraint
        Constraint(),     # constraint data
        1,                # current evaluation number
        [],               # mics. data, perhaps an iteration number for a higher level algorithm
        Symbol,           # optimization status
        Float64,          # solve time for optimization
        Float64,          # objective function value
        [],               # results in DataFrame for plotting
        DataFrame(),      # optimization information in DataFrame for plotting
        []                # constraint data
      )
end

mutable struct Results
  ocp::OCPResults
  ip::PlantResults
  ep::PlantResults
  resultsDir                 # string that defines results folder
  mainDir                    # string that defines main folder
end

function Results()
  Results(
  OCPResults(),
  PlantResults(),
  PlantResults(),
  string(pwd(),"/results/"),  # string that defines results folder
  pwd()                       # string that defines main folder
  )
end

# MPC Settings Class
mutable struct MPCSettings
 on::Bool
 mode::Symbol
 predictX0::Bool
 fixedTp::Bool
 IPKnown::Bool
 saveMode::Symbol
 maxSim::Int64                # maximum number of total MPC updates
 shiftX0::Bool                # a bool to indicate that a check on the feasibility of the linear constraints for the initial conditions should be performed
 lastOptimal::Bool            # a bool to indicate that the previous solution should be used if the current solution in not optimal
 printLevel::Int64
 expandGoal::Bool             # bool to indicate if the goal needs to be expanded
 enlargeGoalTolFactor::Int64  # scaling factor to enlare the goal
 onlyOptimal::Bool
end

function MPCSettings()
      MPCSettings(
      false,
      :OCP,
      false,
      true,
      true,
      :all,
      100,
      true,
      true,
      2,
      true,
      2,
      false
      )
end

# OCP Settings Class
mutable struct OCPSettings
  solver::Solver                # solver information
  finalTimeDV::Bool
  integrationMethod::Symbol
  integrationScheme::Symbol
  save::Bool                    # bool for saving data
  reset::Bool                   # bool for reseting data
  evalConstraints::Bool         # bool for evaluating duals of the constraints
  evalCostates::Bool            # bool for evaluating costates
  tfMin::Any                    # minimum final time
  tfMax::Any                    # maximum final time
  tfOptimal::Any                # known optimal final time
  numInterpPts::Int64           # number of points to sample polynomial running through collocation points
  cacheOnly::Bool               # bool for only caching the results when using optimize!()
  linearInterpolation::Bool     # bool for using linear interpolation even if integrationMethod ==:ps
  interpolationOn::Bool         # bool to indicate if user wants solution interpolated for them
  x0slackVariables::Bool
  xFslackVariables::Bool
end

# Default Constructor NOTE currently not using these, they get overwritten
function OCPSettings()
      OCPSettings(
         Solver(),           # default solver
         false,              # finalTimeDV
         :ts,                # integrationMethod
         :bkwEuler,          # integrationScheme
         true,               # bool for saving data
         false,              # bool for reseting data
         false,              # bool for evaluating duals of the constraints
         false,              # bool for evaluating costates
         0.001,              # minimum final time
         400.0,              # maximum final time
         false,              # known optimal final time
         250,                # number of points to sample polynomial running through collocation points
         false,              # bool for only caching the results when using optimize!()
         false,              # bool for using linear interpolation even if integrationMethod ==:ps
         false,              # bool to indicate if user wants solution interpolated for them
         false,
         false
                )
end

mutable struct Settings
 ocp::OCPSettings
 mpc::MPCSettings
end

function Settings()
 Settings(
  OCPSettings(),
  MPCSettings()
       )
end

"""
L = lagrange_basis_poly(x,x_data,Nc,j)
--------------------------------------------------------------------------------------\n
Author: Huckleberry Febbo, Graduate Student, University of Michigan
Date Create: 12/26/2016, Last Modified: 1/25/2016
Citations: This function was influenced by the lagrange() function [located here](https://github.com/pjabardo/Jacobi.jl/blob/master/src/gauss_quad.jl)
--------------------------------------------------------------------------------------\n
# Input Arguments
* `x`: point to approximate function value at
* `x_data`: x data to used calculate basis polynomials
* `Nc`: order of Lagrange interpolating polynomial
* `j`: index of interest

# Output Arguments
* `L`: Lagrange basis polynomials

A basic description of Lagrange interpolating polynomials is provided [here](http://127.0.0.1:8000/lagrange_poly.html#lagrange-poly)

"""
function lagrange_basis_poly(x,x_data,Nc,j)
    L = 1;
    for idx in 1:Nc+1 # use all of the data
      if idx!=j
        L = L*(x - x_data[idx])/(x_data[j]-x_data[idx]);
      end
    end
  return L
end

"""
y=interpolate_lagrange(ts[int],ts[int],stateMatrix[int][:,st])
--------------------------------------------------------------------------------------\n
Author: Huckleberry Febbo, Graduate Student, University of Michigan
Date Created: 1/2/2017, Last Modified: 9/19/2017 \n
--------------------------------------------------------------------------------------\n
"""
function interpolate_lagrange(x::AbstractArray{T},x_data,y_data) where {T<:Number}
  Nc = length(x_data) - 1

  if length(x_data)!=length(y_data)
      error(string("\n",
                    "-------------------------------------------------------", "\n",
                    "There is an error with the data vector lengths!!", "\n",
                    "-------------------------------------------------------", "\n",
                    "The following variables should be equal:", "\n",
                    "length(x_data) = ",length(x_data),"\n",
                    "length(y_data) = ",length(y_data),"\n"
                    )
            )
    end
    ns = length(x)
    L = zeros(Float64,Nc+1,ns)
    x = x[:]; x_data = x_data[:]; y_data = y_data[:]; # make sure data is in a column
    for idx in 1:Nc+1
      for j in 1:ns
          L[idx,j] = lagrange_basis_poly(x[j],x_data,Nc,idx);
      end
    end
    return y_data'*L
end

"""
--------------------------------------------------------------------------------------\n
Author: Huckleberry Febbo, Graduate Student, University of Michigan
Date Create: 6/29/2017, Last Modified: 12/06/2019 \n
--------------------------------------------------------------------------------------\n
"""
function intervals(n,int,x,u)

  if typeof(x[1,1]) == JuMP.Variable
    # states
    x_int = Array{JuMP.Variable}(length(n.ocp.Nck_full[int]+1:n.ocp.Nck_full[int+1]),n.ocp.state.num)
    for st in 1:n.ocp.state.num # +1 adds the DV in the next interval
      x_int[:,st] = x[n.ocp.Nck_cum[int]+1:n.ocp.Nck_cum[int+1]+1,st];
    end

    # controls
    if int!=n.ocp.Ni
      u_int = Matrix{JuMP.Variable}(undef, length(n.ocp.Nck_full[int]+1:n.ocp.Nck_full[int+1]),n.ocp.control.num)
    else                    # -1 -> removing control in last mesh interval
      u_int = Matrix{JuMP.Variable}(undef, length(n.ocp.Nck_full[int]+1:n.ocp.Nck_full[int+1]-1),n.ocp.control.num)
    end
    for ctr in 1:n.ocp.control.num
      if int!=n.ocp.Ni          # +1 adds the DV in the next interval
        u_int[:,ctr] = u[n.ocp.Nck_cum[int]+1:n.ocp.Nck_cum[int+1]+1,ctr];
      else
        u_int[:,ctr] = u[n.ocp.Nck_cum[int]+1:n.ocp.Nck_cum[int+1],ctr];
      end
    end
  else
    # states
    x_int=Matrix{Any}(undef, length(n.ocp.Nck_full[int]+1:n.ocp.Nck_full[int+1]),n.ocp.state.num);
    for st in 1:n.ocp.state.num # +1 adds the DV in the next interval
      x_int[:,st] = x[n.ocp.Nck_cum[int]+1:n.ocp.Nck_cum[int+1]+1,st];
    end

    # controls
    if int!=n.ocp.Ni
      u_int = Matrix{Any}(undef, length(n.ocp.Nck_full[int]+1:n.ocp.Nck_full[int+1]),n.ocp.control.num)
    else                    # -1 -> removing control in last mesh interval
      u_int = Matrix{Any}(undef, length(n.ocp.Nck_full[int]+1:n.ocp.Nck_full[int+1]-1),n.ocp.control.num)
    end
    for ctr in 1:n.ocp.control.num
      if int!=n.ocp.Ni          # +1 adds the DV in the next interval
        u_int[:,ctr] = u[n.ocp.Nck_cum[int]+1:n.ocp.Nck_cum[int+1]+1,ctr]
      else
        u_int[:,ctr] = u[n.ocp.Nck_cum[int]+1:n.ocp.Nck_cum[int+1],ctr]
      end
    end
  end

  return x_int,u_int
end

"""
--------------------------------------------------------------------------------------\n
Author: Huckleberry Febbo, Graduate Student, University of Michigan
Date Created: 9/19/2017, Last Modified: 12/06/2019 \n
--------------------------------------------------------------------------------------\n
"""
function interpolateLagrange!(n; numPts::Int64=250, tfOptimal::Any=false)
  # TODO throw an error if tfOptimal does not make sense given current solution
  if isa(tfOptimal,Bool)
    if n.s.ocp.finalTimeDV
      tf = getvalue(n.ocp.tf)
    else n.s.ocp.finalTimeDV
      tf = n.ocp.tf
    end
  else  # if there is a known optimal final time, then it is useful to evaluate the Lagrange polynomial at particular points to determine the error in the solution
    tf = tfOptimal
  end

  if isnan(tf)
      @warn "tf is a NaN cannot use it in interpolateLagrange!().\n
            Exiting interpolateLagrange!() without an interpolated solution."
    return nothing
  end

  if tf < 0.01
    @warn "tf needs to be greater than 0.01 to interpolate over solution.\n
          Exiting interpolateLagrange!() without an interpolated solution."
     return nothing
  end

  # sample points
  n.r.ocp.tpolyPts = [range(tf/n.ocp.Ni*(int-1),tf/n.ocp.Ni*int;length=numPts) .+ n.r.ocp.tst[1] for int in 1:n.ocp.Ni]
  n.r.ocp.XpolyPts = [[zeros(numPts) for int in 1:n.ocp.Ni] for st in 1:n.ocp.state.num]
  n.r.ocp.UpolyPts = [[zeros(numPts) for int in 1:n.ocp.Ni] for ctr in 1:n.ocp.control.num]
  if n.s.ocp.evalCostates; n.r.ocp.CSpolyPts = [[zeros(numPts) for int in 1:n.ocp.Ni] for st in 1:n.ocp.state.num] end

  # time data points
  t_st_int = [n.r.ocp.tst[n.ocp.Nck_cum[int]+1:n.ocp.Nck_cum[int+1]+1] for int in 1:n.ocp.Ni]
  t_ctr_int = [n.r.ocp.tctr[n.ocp.Nck_cum[int]+1:n.ocp.Nck_cum[int+1]+1] for int in 1:n.ocp.Ni-1]
  t_ctr_int = push!(t_ctr_int, n.r.ocp.tst[n.ocp.Nck_cum[n.ocp.Ni]+1:n.ocp.Nck_cum[n.ocp.Ni+1]]) # -1 -> removing control in last mesh interval

  for int in 1:n.ocp.Ni
    # controls and states for this interval
    x_int, u_int = intervals(n, int, copy(n.r.ocp.X), copy(n.r.ocp.U))

     # sample polynomial in interval at n.r.ocp.tpolyPts
     for st in 1:n.ocp.state.num
      n.r.ocp.XpolyPts[st][int] = interpolate_lagrange(n.r.ocp.tpolyPts[int], t_st_int[int], x_int[:,st])'
     end

     for ctr in 1:n.ocp.control.num
      n.r.ocp.UpolyPts[ctr][int] = interpolate_lagrange(n.r.ocp.tpolyPts[int], t_ctr_int[int], u_int[:,ctr])'
     end

      # sample polynomial in interval at n.r.ocp.tpolyPts NOTE costate is missing the last point, that is the t_st_int[int][1:end-1]
      if n.s.ocp.evalCostates && n.s.ocp.evalConstraints
         for st in 1:n.ocp.state.num
          n.r.ocp.CSpolyPts[st][int] = interpolate_lagrange(n.r.ocp.tpolyPts[int], t_st_int[int][1:end-1], n.r.ocp.CS[st][int])'
         end
      end
  end

  # extract result into vectors
  temp = [n.r.ocp.tpolyPts[int][1:end] for int in 1:n.ocp.Ni] # time
  n.r.ocp.tpts = [idx for tempM in temp for idx=tempM]
  totalPts = length(n.r.ocp.tpts)

  n.r.ocp.Xpts = Matrix{Float64}(undef, totalPts, n.ocp.state.num)
  for st in 1:n.ocp.state.num # states
    temp = [n.r.ocp.XpolyPts[st][int][1:end,:] for int in 1:n.ocp.Ni]
    n.r.ocp.Xpts[:,st] = [idx for tempM in temp for idx=tempM]
  end

  n.r.ocp.Upts = Matrix{Float64}(undef, totalPts, n.ocp.control.num)
  for ctr in 1:n.ocp.control.num # controls
    temp = [n.r.ocp.UpolyPts[ctr][int][1:end,:] for int in 1:n.ocp.Ni]
    n.r.ocp.Upts[:,ctr] = [idx for tempM in temp for idx=tempM]
  end

  if n.s.ocp.evalCostates && n.s.ocp.evalConstraints
    n.r.ocp.CSpts = Matrix{Float64}(undef, totalPts, n.ocp.state.num)
    for st in 1:n.ocp.state.num # states
      temp = [n.r.ocp.CSpolyPts[st][int][1:end,:] for int in 1:n.ocp.Ni]
      n.r.ocp.CSpts[:,st] = [idx for tempM in temp for idx=tempM]
    end
  end

  return nothing
end

"""
--------------------------------------------------------------------------------------\n
Author: Huckleberry Febbo, Graduate Student, University of Michigan
Date Created: 10/4/2017, Last Modified: 12/06/2019 \n
--------------------------------------------------------------------------------------\n
"""
function interpolateLinear!(n; numPts::Int64=250, tfOptimal::Any=false)
  # TODO throw an error if tfOptimal does not make sense given current solution
  if isa(tfOptimal,Bool)
    if n.s.ocp.finalTimeDV
      tf = getvalue(n.ocp.tf)
    else n.s.ocp.finalTimeDV
      tf = n.ocp.tf
    end
  else  # if there is a known optimal final time, then it is useful to evaluate the Lagrange polynomial at particular points to determine the error in the solution
    tf = tfOptimal
  end

  if isnan(tf)
      @warn "tf is a NaN cannot use it in interpolateLinear!().\n
            Exiting interpolateLinear!() without an interpolated solution."
      return nothing
  end

  if tf < 0.01
    @warn "tf needs to be greater than 0.01 to interpolate over solution.\n
          Exiting interpolateLinear!() without an interpolated solution."
    return nothing
  end

  # sample points
  t = range(0,tf,length=numPts) .+ n.r.ocp.tst[1] # NOTE not tested
  n.r.ocp.tpts = convert(Array{Float64,1},t)
  n.r.ocp.Xpts = Matrix{Float64}(undef, numPts, n.ocp.state.num)
  n.r.ocp.Upts = Matrix{Float64}(undef, numPts, n.ocp.control.num)
  knots = (n.r.ocp.tst,)
  for st in 1:n.ocp.state.num
    sp_st = interpolate(knots,n.r.ocp.X[:,st],Gridded(Linear()))
    n.r.ocp.Xpts[:,st] = sp_st[n.r.ocp.tpts]
  end

  for ctr in 1:n.ocp.control.num
    if isequal(n.s.ocp.integrationMethod,:ps)
      sp_ctr = interpolate(knots,[n.r.ocp.U[:,ctr];0],Gridded(Linear()))
    else
      sp_ctr = interpolate(knots,n.r.ocp.U[:,ctr],Gridded(Linear()))
    end
    n.r.ocp.Upts[:,ctr] = sp_ctr[n.r.ocp.tpts]
  end
  return nothing
end
"""
scale_tau(tau,ta,tb)
--------------------------------------------------------------------------------------\n
Author: Huckleberry Febbo, Graduate Student, University of Michigan
Date Create: 12/23/2017, Last Modified: 12/06/2019 \n
--------------------------------------------------------------------------------------\n
"""
function scale_tau(tau,ta,tb)
  (tb - ta)/2*tau .+ (ta + tb)/2
end

"""
plant2dfs!(n,sol)
--------------------------------------------------------------------------------------\n
Author: Huckleberry Febbo, Graduate Student, University of Michigan
Date Create: 2/14/2017, Last Modified: 12/06/2019 \n
--------------------------------------------------------------------------------------\n
"""
function plant2dfs!(n,sol,U)
  tSample = range(sol.t[1],sol.t[end],length=n.mpc.ip.state.pts)
  dfs = DataFrame()
  if isempty(n.r.ip.plant)
    dfs[:t] = tSample
    for st in 1:n.mpc.ip.state.num
      dfs[n.mpc.ip.state.name[st]] = [sol(t)[st] for t in tSample]
    end
    for ctr in 1:n.mpc.ip.control.num
      dfs[n.mpc.ip.control.name[ctr]] = [U[ctr][t] for t in tSample]
    end
  else
    dfs[:t] = [n.r.ip.plant[:t]; tSample]
    for st in 1:n.mpc.ip.state.num
      dfs[n.mpc.ip.state.name[st]] = [n.r.ip.plant[n.mpc.ip.state.name[st]]; [sol(t)[st] for t in tSample]]
    end
    for ctr in 1:n.mpc.ip.control.num
      dfs[n.mpc.ip.control.name[ctr]] = [n.r.ip.plant[n.mpc.ip.control.name[ctr]]; [U[ctr][t] for t in tSample] ]
    end
  end
  n.r.ip.plant = dfs

  # TODO only run this if saving, it is redundant data, or maybe put time stamps or something in the above data
  dfs = DataFrame()
  dfs[:t] = tSample
  for st in 1:n.mpc.ip.state.num
    dfs[n.mpc.ip.state.name[st]] = [sol(t)[st] for t in tSample]
  end
  for ctr in 1:n.mpc.ip.control.num
    dfs[n.mpc.ip.control.name[ctr]] = [U[ctr][t] for t in tSample]
  end
  push!(n.r.ip.dfsplant,dfs)
  return nothing
end

"""
dvs2dfs(n)
# funtionality to save state, costate, and control data from optimization
--------------------------------------------------------------------------------------\n
Author: Huckleberry Febbo, Graduate Student, University of Michigan
Date Create: 2/10/2017, Last Modified: 12/06/2019 \n
--------------------------------------------------------------------------------------\n
"""
function dvs2dfs(n)
  dfs = DataFrame()
  dfs[:t] = n.r.ocp.tst
  for st in 1:n.ocp.state.num
    dfs[n.ocp.state.name[st]] = n.r.ocp.X[:,st]
  end
  for ctr in 1:n.ocp.control.num
    if n.s.ocp.integrationMethod==:tm
      dfs[n.ocp.control.name[ctr]] = n.r.ocp.U[:,ctr]
    else
      dfs[n.ocp.control.name[ctr]] = [n.r.ocp.U[:,ctr];NaN]
    end
  end

  if n.s.ocp.evalCostates && n.s.ocp.integrationMethod == :ps && n.s.ocp.evalConstraints
    CS_vector = Matrix{Float64}(undef, n.ocp.state.pts, n.ocp.state.num)
    for st in 1:n.ocp.state.num # states
      temp = [n.r.ocp.CS[st][int][1:end,:] for int in 1:n.ocp.Ni]
      CS_vector[1:end-1,st] = [idx for tempM in temp for idx=tempM]
      CS_vector[end,st] = NaN
    end
    for st in 1:n.ocp.state.num # states
      dfs[Symbol(n.ocp.state.name[st],:cs)] = CS_vector[:,st]
    end
  end

  return dfs
end

"""
opt2dfs!(n)
# funtionality to save optimization data
--------------------------------------------------------------------------------------\n
Author: Huckleberry Febbo, Graduate Student, University of Michigan
Date Create: 2/10/2017, Last Modified: 4/13/2018 \n
--------------------------------------------------------------------------------------\n
"""
function opt2dfs!(n;kwargs...)
  kw = Dict(kwargs);

  if !haskey(kw,:statusUpdate); statusUpdate=false;
  else; statusUpdate=get(kw,:statusUpdate,0);
  end

  # make sure that the feildnames are initialized
  if isempty(n.r.ocp.dfsOpt)
      n.r.ocp.dfsOpt = DataFrame(tSolve = [], objVal = [], status = [], iterNum = [], evalNum = [])
  end

  if !statusUpdate
    push!(n.r.ocp.dfsOpt[:tSolve], n.r.ocp.tSolve)
    push!(n.r.ocp.dfsOpt[:objVal], n.r.ocp.objVal)
    push!(n.r.ocp.dfsOpt[:status], n.r.ocp.status)
  else  # TODO consider removing and cleaning this up
    push!(n.r.ocp.dfsOpt[:tSolve], NaN)
    push!(n.r.ocp.dfsOpt[:objVal], NaN)
    if statusUpdate && (typeof(n.r.ocp.status)==Symbol)
      push!(n.r.ocp.dfsOpt[:status], n.r.ocp.status)
    else
      push!(n.r.ocp.dfsOpt[:status], NaN)
    end
  end
  if n.s.mpc.on
    push!(n.r.ocp.dfsOpt[:iterNum], n.r.ocp.iterNum) # can set iter_nums for a higher/lower level algoritm
  end
  push!(n.r.ocp.dfsOpt[:evalNum], n.r.ocp.evalNum-1)

  return nothing
end

"""
con2dfs(n)
# funtionality to save constraint data
--------------------------------------------------------------------------------------\n
Author: Huckleberry Febbo, Graduate Student, University of Michigan
Date Create: 2/20/2017, Last Modified: 4/13/2018 \n
--------------------------------------------------------------------------------------\n
"""
function con2dfs(n)
  dfs_con=DataFrame()
  dfs_con[:conVal]=n.r.ocp.constraint.value;
  return dfs_con
end

"""
postProcess!(n)
--------------------------------------------------------------------------------------\n
Author: Huckleberry Febbo, Graduate Student, University of Michigan
Date Create: 1/27/2017, Last Modified: 12/06/2019 \n
--------------------------------------------------------------------------------------\n
"""
function postProcess!(n;kwargs...)
  kw = Dict(kwargs)
  # check to see if the user is initializing while compensating for control delay
  if !haskey(kw,:Init); Init = false;
  else; Init = get(kw,:Init,0);
  end

  if n.s.ocp.save
    opt2dfs!(n)
  end

  # even if n.r.ocp.status==:Infeasible try to get solution. For the case that user may want to look at results to see where constraints where violated
  # in this case set =>  n.s.ocp.evalConstraints = true
  # http://jump.readthedocs.io/en/latest/refmodel.html#solve-status
  if !Init #&& (n.s.ocp.evalConstraints || ((n.r.ocp.status==:Optimal) || (n.r.ocp.status==:UserLimit)))
    if n.s.ocp.integrationMethod==:ps
      if n.s.ocp.finalTimeDV
        t = [scale_tau(n.ocp.ts[int],0.0,getvalue(n.ocp.tf)) for int in 1:n.ocp.Ni]     # scale time from [-1,1] to [t0,tf]
      else
        t = [scale_tau(n.ocp.ts[int],0.0,n.ocp.tf) for int in 1:n.ocp.Ni]
      end
      n.r.ocp.tctr = [idx for tempM in t for idx = tempM[1:end-1]] .+ getvalue(n.ocp.t0)
      n.r.ocp.tst = [n.r.ocp.tctr; t[end][end] .+ getvalue(n.ocp.t0)]
      # TODO check the above line... is t0 getting added on twice?
    elseif n.s.ocp.integrationMethod==:tm
      if n.s.ocp.finalTimeDV
        n.r.ocp.tctr = append!([0.0],cumsum(getvalue(n.ocp.dt))) .+ getvalue(n.ocp.t0)
      else
        n.r.ocp.tctr = append!([0.0],cumsum(n.ocp.dt)) .+ getvalue(n.ocp.t0)
      end
      n.r.ocp.tst = n.r.ocp.tctr
    end

    stateDataExists = false
    if n.r.ocp.status==:Optimal || (!n.s.mpc.onlyOptimal && n.s.mpc.on && isequal(n.mpc.v.evalNum,1))
      stateDataExists = true
      if (!isequal(n.r.ocp.status,:Optimal) && n.s.mpc.on && isequal(n.mpc.v.evalNum,1))
        @warn "There is no previous :Optimal solution to use since isequal(n.mpc.v.evalNum,1). \n
            Attemting to extract: ",n.r.ocp.status," solution. \n
            Setting: n.f.mpc.simFailed = [true, n.r.ocp.status] "
         n.f.mpc.simFailed = [true, n.r.ocp.status]
      end
      n.r.ocp.X = zeros(Float64,n.ocp.state.pts,n.ocp.state.num)
      n.r.ocp.U = zeros(Float64,n.ocp.control.pts,n.ocp.control.num)
      for st in 1:n.ocp.state.num
        n.r.ocp.X[:,st] = getvalue(n.r.ocp.x[:,st])
      end
      for ctr in 1:n.ocp.control.num
        n.r.ocp.U[:,ctr] = getvalue(n.r.ocp.u[:,ctr])
      end

    elseif n.s.mpc.on && n.s.mpc.lastOptimal && !n.s.mpc.onlyOptimal
      if !n.s.ocp.save
        error("This functionality currently needs to have n.s.ocp.save==true")
      end
      optIdx = findall(n.r.ocp.dfsOpt[:status].==:Optimal)[end]  # use the last :Optimal solution
      @show n.r.ocp.dfsOpt
      @show optIdx
      @show n.r.ocp.dfs[optIdx]
      @show n.mpc.v.t
      if n.r.ocp.dfs[optIdx][:t][1] > n.mpc.v.t
        timeIdx = 1
      elseif n.r.ocp.dfs[optIdx][:t][end] < n.mpc.v.t
        @warn "the current time is past the final time in the last :Optimal soultion.\n
              Setting: n.f.mpc.simFailed = [true, n.r.ocp.status]"
        n.f.mpc.simFailed = [true, n.r.ocp.status]
        return nothing
      else
        timeIdx = findall(n.r.ocp.dfs[optIdx][:t] .- n.mpc.v.t .<= 0)[end]     # find the nearest index in time
      end
      # TODO make an error message or fix      ERROR: LoadError: BoundsError: attempt to access 0-element Array{Int64,1} at index [0]
      n.r.ocp.tst = n.r.ocp.dfs[optIdx][:t][timeIdx:end]
      n.r.ocp.X = zeros(Float64,length(n.r.ocp.dfs[optIdx][n.ocp.state.name[1]][timeIdx:end]),n.ocp.state.num)
      if n.s.ocp.integrationMethod==:tm  # TODO try to
        n.r.ocp.tctr = n.r.ocp.dfs[optIdx][:t][timeIdx:end]
        n.r.ocp.U = zeros(Float64,length(n.r.ocp.dfs[optIdx][n.ocp.control.name[1]][timeIdx:end]),n.ocp.control.num)
      else
        n.r.ocp.tctr = n.r.ocp.dfs[optIdx][:t][timeIdx:end-1]
        n.r.ocp.U = zeros(Float64,length(n.r.ocp.dfs[optIdx][n.ocp.control.name[1]][timeIdx:end-1]),n.ocp.control.num)
      end
      for st in 1:n.ocp.state.num
        n.r.ocp.X[:,st] = n.r.ocp.dfs[optIdx][n.ocp.state.name[st]][timeIdx:end]
      end
      for ctr in 1:n.ocp.control.num
        if n.s.ocp.integrationMethod==:tm
          n.r.ocp.U[:,ctr] = n.r.ocp.dfs[optIdx][n.ocp.control.name[ctr]][timeIdx:end]
        else
          n.r.ocp.U[:,ctr] = n.r.ocp.dfs[optIdx][n.ocp.control.name[ctr]][timeIdx:end-1]
        end
      end
    else
      @warn "The solution is not Optimal \n
          Setting: n.f.mpc.simFailed = [true, n.r.ocp.status] "
       n.f.mpc.simFailed = [true, n.r.ocp.status]
    end
    if n.s.ocp.evalConstraints && n.r.ocp.status!=:Error  # note may want to remove the && arg
      evalConstraints!(n)
      # TODO make a note that costates can only be evaluated if .....
      if n.s.ocp.evalCostates && n.s.ocp.integrationMethod == :ps
        L1 = 0       # find index where dynamics constraints start
        for i in 1:length(n.r.ocp.constraint.name)
          if n.r.ocp.constraint.name[i] == :dyn_con
            L1 = n.r.ocp.constraint.nums[i][end][1]
          end
        end
        mpb = JuMP.internalmodel(n.ocp.mdl)
        c = MathProgBase.getconstrduals(mpb)
        # NOTE for now since costates are not defined for :tm methods, n.r.ocp.CS is in a different format than n.r.ocp.X
        # in the future if costates are defined for :tm methods this can be changed
        n.r.ocp.CS = [[zeros(Float64,n.ocp.Nck[int]) for int in 1:n.ocp.Ni] for st in 1:n.ocp.state.num]
        for int in 1:n.ocp.Ni
          b = 0
          for st in 1:n.ocp.state.num
            a = L1 + n.ocp.Nck[int]*(st-1)  # n.ocp.Nck[int]*(st-1) adds on indices for each additional state within the interval
            b = a + n.ocp.Nck[int] - 1      # length of the state within this interval
            n.r.ocp.CS[st][int] = -c[a:b]./n.ocp.ws[int]
          end
          L1 = b + 1 # adds indicies due to a change in the interval
        end
      end
    end
    if n.s.ocp.save && stateDataExists
      push!(n.r.ocp.dfs,dvs2dfs(n))
      push!(n.r.ocp.dfsCon,con2dfs(n))
      if n.s.ocp.interpolationOn
        if (n.r.ocp.status != :Error) # (n.r.ocp.status != :Infeasible) &&
          if n.s.ocp.integrationMethod==:ps && (n.r.ocp.status != :Infeasible) && !n.s.ocp.linearInterpolation
            interpolateLagrange!(n;numPts = n.s.ocp.numInterpPts, tfOptimal = n.s.ocp.tfOptimal)
            push!(n.r.ocp.AlltpolyPts,n.r.ocp.tpolyPts)
            push!(n.r.ocp.AllXpolyPts,n.r.ocp.XpolyPts)
            push!(n.r.ocp.AllUpolyPts,n.r.ocp.UpolyPts)
            if n.s.ocp.evalCostates && n.s.ocp.evalConstraints
              push!(n.r.ocp.AllCSpolyPts,n.r.ocp.CSpolyPts)
            end
          else
            interpolateLinear!(n;numPts = n.s.ocp.numInterpPts, tfOptimal = n.s.ocp.tfOptimal)
            if n.s.ocp.integrationMethod==:ps && !n.s.ocp.linearInterpolation
              push!(n.r.ocp.AlltpolyPts,nothing)
              push!(n.r.ocp.AllXpolyPts,nothing)
              push!(n.r.ocp.AllUpolyPts,nothing)
              if n.s.ocp.evalCostates && n.s.ocp.evalConstraints
                push!(n.r.ocp.AllCSpolyPts,nothing)
              end
            end
          end
        end
      end  # TODO save [] of interpolated pts for :tm methods
    end
  end
  return nothing
end
# TODO add some "finalPostProcess" to sace time
"""
optimize!(n)
# solves JuMP model and saves optimization data
--------------------------------------------------------------------------------------\n
Author: Huckleberry Febbo, Graduate Student, University of Michigan
Date Create: 2/6/2017, Last Modified: 4/13/2018 \n
--------------------------------------------------------------------------------------\n
"""
function optimize!(n;Iter::Int64=0)
  t1 = time(); status = JuMP.solve(n.ocp.mdl); t2 = time();
  if !n.s.ocp.cacheOnly
    n.r.ocp.status = status
    n.r.ocp.tSolve = t2 - t1
    n.r.ocp.objVal = getobjectivevalue(n.ocp.mdl)
    n.r.ocp.iterNum = Iter    # possible iteration number for a higher level algorithm
    n.r.ocp.evalNum = n.r.ocp.evalNum + 1
    postProcess!(n)      # temporarily save data
  end
  return nothing
end
"""
--------------------------------------------------------------------------------------\n
Author: Huckleberry Febbo, Graduate Student, University of Michigan
Date Create: 2/7/2017, Last Modified: 4/13/2018 \n
--------------------------------------------------------------------------------------\n
"""
function evalConstraints!(n)
  n.r.ocp.constraint.value=[];   # reset values
  n.r.ocp.constraint.nums=[]; s=1;
  for i = 1:length(n.r.ocp.constraint.handle)
    if n.r.ocp.constraint.name[i]==:dyn_con  # state constraits
      dfs=Vector{DataFrame}(n.ocp.state.num);
      con=DataFrame(step=1);
      l=0;
      for st in 1:n.ocp.state.num
        if n.s.ocp.integrationMethod==:ps
          temp=[getdual(n.r.ocp.constraint.handle[i][int][:,st]) for int in 1:n.ocp.Ni];
          vals=[idx for tempM in temp for idx=tempM];
          dfs[st]=DataFrame(step=1:sum(n.ocp.Nck);Dict(n.ocp.state.name[st] => vals)...);
          l=l+length(vals);
        else
          dfs[st]=DataFrame(step=1:n.ocp.N;Dict(n.ocp.state.name[st] => getdual(n.r.ocp.constraint.handle[i][:,st]))...);
          l=l+length(n.r.ocp.constraint.handle[i][:,st]);
        end
        if st==1; con=dfs[st]; else; con=join(con,dfs[st],on=:step); end
      end
    else
      S=0;
      try
        S=JuMP.size(n.r.ocp.constraint.handle[i])
      catch
        error("\n For now, the constraints cannot be in this form: \n
        con=@NLconstraint(mdl,n.r.ocp.u[1,1]==param); \n
        Write it in array form: \n
          con=@NLconstraint(mdl,[i=1],n.r.ocp.u[i,1]==param); \n")
      end
      if length(S)==1
        con = DataFrame(step=1:length(n.r.ocp.constraint.handle[i]);Dict(n.r.ocp.constraint.name[i] => getdual(n.r.ocp.constraint.handle[i][:]))...);
        l=S[1];
      elseif length(S)==2
        dfs=Vector{DataFrame}(S[1]);
        con=DataFrame(step=1);
        for idx in 1:S[1]
          try
            dfs[idx] = DataFrame(step=1:S[2];Dict(n.r.ocp.constraint.name[i] => getdual(n.r.ocp.constraint.handle[i][idx,:]))...);
          catch
            dfs[idx] = DataFrame(step=1:S[2];Dict(n.r.ocp.constraint.name[i] => NaN)...); # fix for case where all of the states are not being constrainted, but some are within some XF_tol
          end
          if idx==1;
            con = dfs[idx]
          else
            con = join(con,dfs[idx],on=:step,makeunique=true)
          end
        end
        l = S[1]*S[2]
      end
    end
    f = s + l - 1
    num = (i,n.r.ocp.constraint.name[i],@sprintf("length = %0.0f",l),string("indecies in g(x) = "),(s,f))
    push!(n.r.ocp.constraint.nums,num)
    push!(n.r.ocp.constraint.value,con)
    s = f + 1
  end
  return nothing
end

"""
description = string(
" *  \n ")

resultsDir!(r;resultsName=resultsName,description=description)
# removes results folder and creates a new one
# TODO consider putting in a warning or some sort of an interaction with user
--------------------------------------------------------------------------------------\n
Author: Huckleberry Febbo, Graduate Student, University of Michigan
Date Create: 3/26/2017, Last Modified: 5/29/2017 \n
--------------------------------------------------------------------------------------\n
"""
function resultsDir!(n;resultsName::String = "",description::DataFrame = DataFrame())
 results_dir=string(n.r.mainDir,"/results/",resultsName)  # define directories
 n.r.resultsDir=results_dir;

 if isdir(n.r.resultsDir)
   rm(n.r.resultsDir; recursive=true)
   print("\n The old results have all been deleted! \n \n")
 end
 mkdir(n.r.resultsDir)# create directory

 cd(n.r.resultsDir)
   CSV.write("description.csv", description; quotechar = ' ')
 cd(n.r.mainDir)
 return nothing
end

end # module
