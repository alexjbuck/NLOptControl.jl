module MPC_Module

using JuMP
using OrdinaryDiffEq
using DiffEqBase

include("Base.jl")
using .Base

export
     MPC,
     defineMPC!,
     initOpt!,
     defineIP!,
     mapNames!,
     simIPlant!,
     updateX0!,
     currentIPState,
     goalReached!,
     simMPC!,
     predictX0!

########################################################################################
# MPC structs
########################################################################################

mutable struct IP
 control::Control
 state::State
end

function IP()
 IP(
  Control(),
  State()
  )
end

mutable struct EP
 control::Control
 state::State
end

function EP()
 EP(
  Control(),
  State()
 )
end

mutable struct MPCvariables
 # variables
 t::Float64           # current simulation time (s)
 tp::Any              # prediction time (if finalTimeDV == true -> this is not known before optimization)
 tex::Float64         # execution horizon time
 t0Actual                    # actual initial time TODO ?
 t0::Float64                  # mpc initial time TODO ?
 tf::Float64                  # mpc final time TODO ?
 t0Param::Any        # parameter for mpc t0  TODO ?
 evalNum::Int64       # parameter for keeping track of number of MPC evaluations
 goal                 # goal location w.r.t OCP
 goalTol             # tolerance on goal location
 initOptNum::Int64  # number of initial optimization
 previousSolutionNum::Int64  # number of times the previous solution should be used
end

function MPCvariables()
 MPCvariables(
              0.0,    # t
              Any,    # tp (might be a variable)
              0.5,    # tex
              0.0,
              0.0,
              0.0,
              Any,
              1,
              [],
              [],
              3,
              3
 )
end

mutable struct MPC
 v::MPCvariables
 ip::IP
 ep::EP
end

function MPC()
 MPC(
     MPCvariables(),
     IP(),
     EP()
     )
end

########################################################################################
# MPC functions
########################################################################################
"""
defineMPC!(n)
--------------------------------------------------------------------------------------\n
Author: Huckleberry Febbo, Graduate Student, University of Michigan
Date Create: 4/7/2017, Last Modified: 4/8/2018 \n
--------------------------------------------------------------------------------------\n
"""
function defineMPC!(n;
                   mode::Symbol=:OCP,
                   predictX0::Bool=true,
                   fixedTp::Bool=true,
                   tp::Any=Any,
                   tex::Float64=0.5,
                   IPKnown::Bool=true,
                   saveMode::Symbol=:all,
                   maxSim::Int64=100,
                   goal=n.ocp.XF,
                   goalTol=0.1*abs.(n.ocp.X0 - n.ocp.XF),
                   lastOptimal::Bool=true,
                   printLevel::Int64=2,
                   onlyOptimal::Bool=false)
 n.s.mpc.on = true
 n.mpc::MPC = MPC()
 n.s.mpc.mode = mode
 n.s.mpc.predictX0 = predictX0
 n.s.mpc.fixedTp = fixedTp
 n.mpc.v.tp = tp
 n.mpc.v.tex = tex
 n.s.mpc.IPKnown = IPKnown
 n.s.mpc.saveMode = saveMode
 n.s.mpc.maxSim = maxSim
 n.mpc.v.goal = goal
 n.mpc.v.goalTol = goalTol
 n.s.mpc.lastOptimal = lastOptimal
 n.s.mpc.printLevel = printLevel
 n.s.mpc.onlyOptimal = onlyOptimal

 n.f.mpc.simFailed[1] = false # for some reason it is getting defined as 0.0, not false during initialization
 n.f.mpc.defined = true
 return nothing
end

"""
# TODO consider letting user pass options
--------------------------------------------------------------------------------------\n
Author: Huckleberry Febbo, Graduate Student, University of Michigan
Date Create: 4/08/2018, Last Modified: 12/06/2019 \n
--------------------------------------------------------------------------------------\n
"""
function initOpt!(n;save::Bool=true, evalConstraints::Bool=false)
  if n.s.mpc.on
   error("call initOpt!() before defineMPC!(). initOpt!() will destroy n")
  end
  n.s.ocp.save = false
  n.s.mpc.on = false
  n.s.ocp.evalConstraints = false
  n.s.ocp.cacheOnly = true
  if n.s.ocp.save
   @warn "saving initial optimization results where functions where cached!"
  end
  for k in 1:n.mpc.v.initOptNum # initial optimization (s)
   status = optimize!(n)
   if status==:Optimal; break; end
  end
  # defineSolver!(n,solverConfig(c)) # modifying solver settings NOTE currently not in use
  n.s.ocp.save = save  # set to false if running in parallel to save time
  n.s.ocp.cacheOnly = false
  n.s.ocp.evalConstraints = evalConstraints # set to true to investigate infeasibilities
  return nothing
end

"""
# add a mode that solves as quickly as possible
# consider using the IP always.
defineModel!(n)
--------------------------------------------------------------------------------------\n
Author: Huckleberry Febbo, Graduate Student, University of Michigan
Date Create: 4/12/2018, Last Modified: 4/12/2018 \n
--------------------------------------------------------------------------------------\n
"""
function defineIP!(n,model;stateNames=[],controlNames=[],X0a=[])

   if isequal(n.s.mpc.mode,:OCP) # this function is called automatically for this mode
    if !isempty(stateNames)
     error("stateNames are set automatically for :mode == :OCP and cannot be provided.")
    end
    if !isempty(controlNames)
     error("controlNames are set automatically for :mode == :OCP and cannot be provided.")
    end
    if !isempty(X0a)
     error("X0a is set automatically for :mode == :OCP and cannot be provided.")
    end
    n.r.ip.X0a = copy(n.ocp.X0)  # NEED to append time
    n.mpc.ip.state.model = model
    n.mpc.ip.state.name = n.ocp.state.name
    n.mpc.ip.state.description = n.ocp.state.description
    n.mpc.ip.state.num = n.ocp.state.num
    n.mpc.ip.state.pts = n.ocp.state.pts

    n.mpc.ip.control.name = n.ocp.control.name
    n.mpc.ip.control.description = n.ocp.control.description
    n.mpc.ip.control.num = n.ocp.control.num
    n.mpc.ip.control.pts = n.ocp.control.pts

    # add X0 t0 plant dfs
    n.r.ip.plant[:t] = n.mpc.v.t0
    for st in 1:n.mpc.ip.state.num
      n.r.ip.plant[n.mpc.ip.state.name[st]] = copy(n.ocp.X0)[st]
    end
    for ctr in 1:n.mpc.ip.control.num
      n.r.ip.plant[n.mpc.ip.control.name[ctr]] = 0
    end

   elseif isequal(n.s.mpc.mode,:IP)
    if isempty(stateNames)
     error("unless :mode == :OCP the stateNames must be provided.")
    end
    if isempty(controlNames)
     error("unless :mode == :OCP the controlNames must be provided.")
    end
    if isempty(X0a)
     error("unless :mode == :OCP X0a must be provided.")
    end
    if isempty(model)
     error("A model needs to be passed for the IP mode.")
    else
    if isequal(length(X0a),length(stateNames))
      error(string("\n Length of X0a must match length(stateNames) \n"))
    end

     n.mpc.ip.state::State = State() # reset
     n.mpc.ip.state.num = length(stateNames)
     for i in 1:n.mpc.ip.state.num
       if stateNames[i]==:xxx
         error("xxx is OFF limits for a state name; please choose something else. \n")
       end
       push!(n.mpc.ip.state.name,stateNames[i])
     end

     n.mpc.ip.control::Control = Control() # reset
     n.mpc.ip.control.num = length(controlNames)
     for i in 1:n.mpc.ip.control.num
       if controlNames[i]==:xxx
         error("xxx is OFF limits for a control name; please choose something else. \n")
       end
       push!(n.mpc.ip.control.name,controlNames[i])
     end
     n.mpc.r.ip.X0a = X0a
     n.mpc.ip.state.model = model # TODO validate typeof model
    end
   elseif isequal(n.s.mpc.mode,:EP)
    error("not setup for :EP")
   else
    error("n.mpc.s.mode = ",n.s.mpc.mode," not defined." )
   end

   # consider calling mapNames
   return nothing
end

"""
mapNames!(n)
--------------------------------------------------------------------------------------\n
Author: Huckleberry Febbo, Graduate Student, University of Michigan
Date Create: 4/9/2018, Last Modified: 4/12/2018 \n
--------------------------------------------------------------------------------------\n
"""
function mapNames!(n)
  if isequal(n.s.mpc.mode,:IP)
    s1 = n.ocp.state.name
    c1 = n.ocp.control.name
    s2 = n.mpc.ip.state.name
    c2 = n.mpc.ip.control.name
  elseif isequal(n.s.mpc.mode,:EP)
    error(":EP function not ready")
  else
    error("mode must be either :IP or :EP")
  end

  m = []
  # go through all states in OCP
  idxOCP = 1
  for var in s1
    # go through all states in IP
    idxIP = findall(var.==s2)
    if !isempty(idxIP)
      push!(m, [var; :stOCP; idxOCP; :stIP; idxIP[1]])
    end

    # go through all controls in IP
    idxIP = findall(var.==c2)
    if !isempty(idxIP)
      push!(m, [var; :stOCP; idxOCP; :ctrIP; idxIP[1]])
    end
    idxOCP = idxOCP + 1
  end

  # go through all controls in OCP
  idxOCP = 1
  for var in c1
    # go through all states in IP
    idxIP = findall(var.==s2)
    if !isempty(idxIP)
      push!(m, [var; :ctrOCP; idxOCP; :stIP; idxIP[1]])
    end

    # go through all controls in IP
    idxIP = findall(var.==c2)
    if !isempty(idxIP)
      push!(m, [var; :ctrOCP; idxOCP; :ctrIP; idxIP[1]])
    end
    idxOCP = idxOCP + 1
  end

  if isequal(n.s.mpc.mode,:IP)
    n.mpc.mIP = m
  elseif isequal(n.s.mpc.mode,:EP)
    error(":EP function not ready")
  else
    error("mode must be either :IP or :EP")
  end

  return nothing
end

"""
# TODO fix this so that prediction simulation time is ahead. May not effect results.
# NOTE this may be ok... we are getting X0p for initialization of the OCP
# as long as the OCP pushes the time ahead. which it does then everything is fine!!
# consider making user pass X0, t0, tf
--------------------------------------------------------------------------------------\n
Author: Huckleberry Febbo, Graduate Student, University of Michigan
Date Create: 2/14/2017, Last Modified: 12/06/2019 \n
--------------------------------------------------------------------------------------\n
"""
function simIPlant!(n)
  if isequal(n.mpc.ip.state.pts,0)
   error("isqual(n.mpc.ip.state.pts,0), cannot simulate with zero points.")
  end
  X0 = currentIPState(n)[1]
  t0 = round(n.mpc.v.t,3) # if rounding is too rough, then the tex will be essentially 0!
  tf = round(n.mpc.v.t + n.mpc.v.tex,3)

  if isequal(n.s.mpc.mode,:OCP)
   if isequal(n.mpc.v.evalNum,1)
    U = 0*Matrix{Float64}(undef, n.ocp.control.pts,n.ocp.control.num)
    t = Vector(range(t0,tf,length=n.ocp.control.pts))
   elseif n.s.ocp.interpolationOn
    U = n.r.ocp.Upts
    t = n.r.ocp.tpts
   else
    U = n.r.ocp.U
    t = n.r.ocp.tctr
   end
  else
   error("TODO")
  end
  # chop of first control point for bkwEuler as it is typically 0
  if isequal(n.s.ocp.integrationScheme,:bkwEuler)
   U = U[2:end,:]
   t = t[2:end]
  end

  sol, U = n.mpc.ip.state.model(n,X0,t,U,t0,tf)
  return sol, U
end

"""
--------------------------------------------------------------------------------------\n
Author: Huckleberry Febbo, Graduate Student, University of Michigan
Date Create: 4/08/2018, Last Modified: 4/08/2018 \n
--------------------------------------------------------------------------------------\n
"""
function currentIPState(n)
  if isempty(n.r.ip.plant)
    error("there is no data in n.r.ip.plant")
  end

  # even though may have solution for plant ahead of time
  # can only get the state up to n.mpc.v.t
  idx = findall((n.mpc.v.t .- n.r.ip.plant[:t]) .>= 0)
  if isempty(idx)
    error("(n.mpc.v.t - n.r.ip.plant[:t]) .>= 0) is empty.")
  else
    X0 = [zeros(n.mpc.ip.state.num),n.mpc.v.t]
    for st in 1:n.mpc.ip.state.num
      X0[1][st] = n.r.ip.plant[n.mpc.ip.state.name[st]][idx[end]]
    end
  end
  return X0
end

"""
# TODO eventually the "plant" will be different from the "model"
predictX0!(n)
--------------------------------------------------------------------------------------\n
Author: Huckleberry Febbo, Graduate Student, University of Michigan
Date Create: 4/7/2017, Last Modified: 4/25/2018 \n
--------------------------------------------------------------------------------------\n
"""
function predictX0!(n)

  if n.s.mpc.fixedTp
   # NOTE consider passing back (n.mpc.v.t + n.mpc.v.tex) from simIPlant!()
   tp = round(n.mpc.v.t + n.mpc.v.tex,1)  # TODO add 1 as an MPCparamss
  else
   error("TODO")
  end

  if isequal(n.s.mpc.mode,:OCP)
   sol, U = simIPlant!(n)
   X0p = [sol(sol.t[end])[:],tp]
   push!(n.r.ip.X0p,X0p)
  else
    error("TODO")
  end
 # else
   # with no control signals to follow, X0p is simply the current known location of the plant
 #  X0 = currentIPState(n)
 #  X0p = [X0[1], tp]  # modify X0 to predict the time
  # push!(n.r.ip.X0p,X0p)
 # end
  return nothing
end

"""
--------------------------------------------------------------------------------------\n
Author: Huckleberry Febbo, Graduate Student, University of Michigan
Date Create: 3/06/2018, Last Modified: 4/08/2018 \n
--------------------------------------------------------------------------------------\n
"""
function updateX0!(n,args...)
 # need to map n.r.ip.X0p to n.X0 (states may be different)
 # NOTE for the :OCP mode this is OK

 if !n.s.mpc.predictX0 #  use the current known plant state to update OCP
   push!(n.r.ip.X0p,currentIPState(n))
 else
   predictX0!(n)
 end

 if isequal(n.s.mpc.mode,:OCP)
   if !isequal(length(args),0)
    X0 = args[1]
    if length(X0)!=n.ocp.state.num
      error(string("\n Length of X0 must match number of states \n"));
    end
    n.ocp.X0 = X0
   else
    n.ocp.X0 = n.r.ip.X0p[end][1] # the n.ocp. structure is for running things
   end
   push!(n.r.ocp.X0,n.ocp.X0)    # NOTE this may be for saving data
   setvalue(n.ocp.t0,copy(n.r.ip.X0p[end][2]))
 else
  error("not set up for this mode")
 end

  if n.s.mpc.shiftX0 # TODO consider saving linear shifting occurances
    for st in 1:n.ocp.state.num
      if n.ocp.X0[st] < n.ocp.XL[st]
        n.ocp.X0[st] = n.ocp.XL[st]
      end
      if n.ocp.X0[st] > n.ocp.XU[st]
        n.ocp.X0[st] = n.ocp.XU[st]
      end
    end
  end
  # update states with n.ocp.X0
  for st in 1:n.ocp.state.num
    if n.s.ocp.x0slackVariables
     JuMP.setRHS(n.r.ocp.x0Con[st,1], n.ocp.X0[st])
     JuMP.setRHS(n.r.ocp.x0Con[st,2],-n.ocp.X0[st])
    else
      JuMP.setRHS(n.r.ocp.x0Con[st],n.ocp.X0[st])
    end
  end
  return nothing
end


"""
--------------------------------------------------------------------------------------\n
Author: Huckleberry Febbo, Graduate Student, University of Michigan
Date Create: 4/08/2018, Last Modified: 4/08/2018 \n
--------------------------------------------------------------------------------------\n
"""
function goalReached!(n,args...)
  if isequal(n.s.mpc.mode,:OCP)
    X = currentIPState(n)[1]
  else
    X = args[1]
    error("TODO")
  end
  A = (abs.(X - n.mpc.v.goal) .<= n.mpc.v.goalTol)
  B = isnan.(n.mpc.v.goal)
  C = [A[i]||B[i] for i in 1:length(A)]

  if all(C)
   if isequal(n.s.mpc.printLevel,2)
    println("Goal Attained! \n")
   end
    n.f.mpc.goalReached = true
  elseif n.s.mpc.expandGoal && (getvalue(n.ocp.tf) < n.mpc.v.tex)
    A =( abs.(X - n.mpc.v.goal) .<= n.s.mpc.enlargeGoalTolFactor*n.mpc.v.goalTol)
    C = [A[i]||B[i] for i in 1:length(A)]
    if all(C)
     if isequal(n.s.mpc.printLevel,2)
      println("Expanded Goal Attained! \n")
     end
     n.f.mpc.goalReached = true
    else
     println("Expanded Goal Not Attained! \n
              Stopping Simulation")
     n.f.mpc.simFailed = [true, :expandedGoal]
    end
  end

 return n.f.mpc.goalReached
end
# if the vehicle is very close to the goal sometimes the optimization returns with a small final time
# and it can even be negative (due to tolerances in NLP solver). If this is the case, the goal is slightly
# expanded from the previous check and one final check is performed otherwise the run is failed
#if getvalue(n.ocp.tf) < 0.01
#  if ((n.r.ip.dfplant[end][:x][end]-c["goal"]["x"])^2 + (n.r..ip.dfplant[end][:y][end]-c["goal"]["yVal"])^2)^0.5 < 2*c["goal"]["tol"]
#  println("Expanded Goal Attained! \n"); n.f.mpc.goal_reached=true;
#  break;/
#  else
#  warn("Expanded Goal Not Attained! -> stopping simulation! \n"); break;
#  end
#elseif getvalue(n.ocp.tf) < 0.5 # if the vehicle is near the goal => tf may be less then 0.5 s
#  tf = (n.r.evalNum-1)*n.mpc.v.tex + getvalue(n.ocp.tf)
#else
#  tf = (n.r.evalNum)*n.mpc.v.tex
#end


"""
--------------------------------------------------------------------------------------\n
Author: Huckleberry Febbo, Graduate Student, University of Michigan
Date Create: 2/06/2018, Last Modified: 4/08/2018 \n
--------------------------------------------------------------------------------------\n
"""
function simMPC!(n;updateFunction::Any=[],checkFunction::Any=[])
  for ii = 1:n.s.mpc.maxSim
    if isequal(n.s.mpc.printLevel,2)
     println("Running model for the: ",n.mpc.v.evalNum," time")
    end
    #############################
    # (A) and (B) in "parallel"
    #############################

    # (B) simulate plant
    sol, U = simIPlant!(n) # the plant simulation time will lead the actual time
    plant2dfs!(n,sol,U)

    # check to see if the simulation failed (i.e. plant crashed)
    if !isequal(typeof(checkFunction),Array{Any,1})
     val, sym = checkFunction(n)
     if val
       n.f.mpc.simFailed = [val, sym]
      break
     end
    end

    # check to see if the goal has been reached
    if goalReached!(n); break; end
    if n.f.mpc.simFailed[1]; break; end

    # (A) solve OCP  TODO the time should be ahead here as it runs
    updateX0!(n)  # before updateFunction()
    if !isequal(typeof(updateFunction),Array{Any,1})
      updateFunction(n)
    end

    optimize!(n)
    if n.f.mpc.simFailed[1]; break; end

    # advance time
    n.mpc.v.t = n.mpc.v.t + n.mpc.v.tex
    n.mpc.v.evalNum = n.mpc.v.evalNum + 1
  end
end
# practical concerns/questions
#################################
# 1) predict X0
# 2) shift X0 for NLP feasibility
# 3) ensuring that U passed to the plant is feasible
     # effected by interpolation, demonstrate by varying numPts
     # seems to be a major problem with LGR nodes, possibly due to Runge effect
# 4) fixedTp or variableTp
# 5) usePrevious optimal.
     # at some point will be unable to do this
# 6) infeasibilities, soft constraint on inital conditions

# TODO
# 1) plot the goal, the tolerances on X0p
# 2) calculate the error and plot
end # module
