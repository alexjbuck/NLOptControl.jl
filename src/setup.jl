"""
n = define(numStates=2,numControls=2,Ni=4,Nck=[3, 3, 7, 2];(:finalTimeDV => false));
--------------------------------------------------------------------------------------\n
Author: Huckleberry Febbo, Graduate Student, University of Michigan
Date Create: 1/1/2017, Last Modified: 1/20/2017 \n
Citations: \n
----------\n
Initially Influenced by: S. Hughes.  steven.p.hughes@nasa.gov
Source: DecisionVector.m [located here](https://sourceforge.net/p/gmat/git/ci/264a12acad195e6a2467cfdc68abdcee801f73fc/tree/prototype/OptimalControl/LowThrust/@DecisionVector/)
-------------------------------------------------------------------------------------\n
"""
function define(n::NLOpt;
                numStates::Int64=0,
                numControls::Int64=0,
                X0::Array{Float64,1}=zeros(Float64,numStates,1),
                XF::Array{Float64,1}=zeros(Float64,numStates,1),
                XL::Array{Float64,1}=zeros(Float64,numStates,1),
                XU::Array{Float64,1}=zeros(Float64,numStates,1),
                CL::Array{Float64,1}=zeros(Float64,numControls,1),
                CU::Array{Float64,1}=zeros(Float64,numControls,1)
                )

  # validate input
  if  numStates <= 0
      error("\n numStates must be > 0","\n",
              "default value = 0","\n",
            );
  end
  if  numControls <= 0
      error("eventually numControls must be > 0","\n",
            "default value = 0","\n",
            );
  end
  if length(X0) != numStates
    error(string("\n Length of X0 must match number of states \n"));
  end
  if length(XF) != numStates
    error(string("\n Length of XF must match number of states \n"));
  end
  if length(XL) != numStates
    error(string("\n Length of XL must match number of states \n"));
  end
  if length(XU) != numStates
    error(string("\n Length of XU must match number of states \n"));
  end
  if length(CL) != numControls
    error(string("\n Length of CL must match number of controls \n"));
  end
  if length(CU) != numControls
    error(string("\n Length of CU must match number of controls \n"));
  end

  n.numStates = numStates;
  n.numControls = numControls;
  n.X0 = X0;
  n.XF = XF;
  n.XL = XL;
  n.XU = XU;
  n.CL = CL;
  n.CU = CU;
  return n
end

"""
n = configure(n::NLOpt,Ni=4,Nck=[3, 3, 7, 2];(:integrationMethod => ps),(:integrationScheme => lgrExplicit),(:finalTimeDV => false));
--------------------------------------------------------------------------------------\n
Author: Huckleberry Febbo, Graduate Student, University of Michigan
Date Create: 1/1/2017, Last Modified: 1/23/2017 \n
Citations: \n
----------\n
Initially Influenced by: S. Hughes.  steven.p.hughes@nasa.gov
Source: DecisionVector.m [located here](https://sourceforge.net/p/gmat/git/ci/264a12acad195e6a2467cfdc68abdcee801f73fc/tree/prototype/OptimalControl/LowThrust/@DecisionVector/)
-------------------------------------------------------------------------------------\n
"""
function configure(n::NLOpt, args...; kwargs... )
  kw = Dict(kwargs);

  # final time
  if !haskey(kw,:finalTimeDV); kw_ = Dict(:finalTimeDV => false); finalTimeDV = get(kw_,:finalTimeDV,0);
  else; finalTimeDV  = get(kw,:finalTimeDV,0);
  end

  if !haskey(kw,:tf) && !finalTimeDV
    error("\n If the final is not a design variable pass it as: (:tf=>Float64(some #)) \n
        If the final time is a design variable, indicate that as: (:finalTimeDV=>true)\n")
  elseif haskey(kw,:tf) && !finalTimeDV
    tf = get(kw,:tf,0);
  elseif finalTimeDV
    tf = NaN;
  end

  # integration method
  if !haskey(kw,:integrationMethod); kw_ = Dict(:integrationMethod => :ps); integrationMethod = get(kw_,:integrationMethod,0);
  else; integrationMethod  = get(kw,:integrationMethod,0);
  end

  if integrationMethod==:ps
    if haskey(kw,:N)
      error(" \n N is not an appropriate kwargs for :tm methods \n")
    end
    if !haskey(kw,:Ni); kw_ = Dict(:Ni => 1); const Ni=get(kw_,:Ni,0);        # default
    else; const Ni = get(kw,:Ni,0);
    end
    if !haskey(kw,:Nck); kw_ = Dict(:Nck => [10]); const Nck=get(kw_,:Nck,0); # default
    else; const Nck = get(kw,:Nck,0);
    end
    if !haskey(kw,:integrationScheme); kw_ = Dict(:integrationScheme => :lgrExplicit);const integrationScheme=get(kw_,:integrationScheme,0); # default
    else; const integrationScheme=get(kw,:integrationScheme,0);
    end
    if length(Nck) != Ni
        error("\n length(Nck) != Ni \n");
    end
    for int in 1:Ni
        if (Nck[int]<0)
            error("\n Nck must be > 0");
        end
    end
    if  Ni <= 0
      error("\n Ni must be > 0 \n");
    end
    const numPoints = [Nck[int] for int in 1:Ni];  # number of design variables per interval

    # initialize node data
    if integrationScheme==:lgrExplicit
      taus_and_weights = [gaussradau(Nck[int]) for int in 1:Ni];
    end
    τ = [taus_and_weights[int][1] for int in 1:Ni];
    ω = [taus_and_weights[int][2] for int in 1:Ni];
    if finalTimeDV   # initialize scaled variables as zeros
      ts = 0*τ; ωₛ = 0*ω;
    else
      ts, ωₛ = create_intervals(t0,tf,Ni,Nck,τ,ω);
    end

  elseif integrationMethod==:tm
    if haskey(kw,:Nck) || haskey(kw,:Ni)
      error(" \n Nck and Ni are not appropriate kwargs for :tm methods \n")
    end
    if !haskey(kw,:N); kw_ = Dict(:N => 10); const N=get(kw_,:N,0); # default
    else; const N = get(kw,:N,0);
    end
    if !haskey(kw,:integrationScheme); kw_ = Dict(:integrationScheme => :bkwEuler); const integrationScheme=get(kw_,:integrationScheme,0); # default
    else; const integrationScheme=get(kw,:integrationScheme,0);
    end
  end

end
"""
nlp2ocp(nlp,ps);
--------------------------------------------------------------------------------------\n
Author: Huckleberry Febbo, Graduate Student, University of Michigan
Date Create: 1/2/2017, Last Modified: 1/4/2017 \n
--------------------------------------------------------------------------------------\n
"""
# to do, pack decisionVector into nlp
function nlp2ocp(nlp::NLP_data,ps::PS_data)
    @unpack t0, tf, stateMatrix, controlMatrix, Ni, Nck = ps
    @unpack stateIdx_all, controlIdx_all, timeStartIdx, timeStopIdx = nlp
    @unpack stateIdx, controlIdx = nlp
    @unpack numStates, numControls, lengthDecVector = nlp
    @unpack decisionVector = nlp

    if length(decisionVector)!=lengthDecVector
      error(string("\n",
                    "-------------------------------------", "\n",
                    "There is an error with the indecies!!", "\n",
                    "-------------------------------------", "\n",
                    "The following variables should be equal:", "\n",
                    "length(decisionVector) = ",length(decisionVector),"\n",
                    "lengthDecVector = ",lengthDecVector,"\n"
                    )
            )
    end
    # update parameters
    t0 = decisionVector[timeStartIdx];
    tf = decisionVector[timeStopIdx];

    # the state matrix is sized according to eq. (40) in the GPOPS II article
    # n is the total number of states -> the individual states are columns
    # V[int]      = [X11               X21      ...      Xn1;
    #                X12               X22      ...      Xn2;
    #                .                  .                 .
    #                .                  .                 .
    #                .                  .                 .
    #         X1_{Nck[int]+1}    X2_{Nck[int]+1}   Xn_{Nck[int]+1}

    stateMatrix = [zeros(Nck[int]+1, numStates) for int in 1:Ni];
    idx = 1;
    for int in 1:Ni
        for st in 1:numStates
            if numStates > 1
              stateMatrix[int][:,st] = decisionVector[stateIdx_all[idx][1]:stateIdx_all[idx][2]]
            else # use indexing for single state variable
              stateMatrix[int][:,st] = decisionVector[stateIdx[idx][1]:stateIdx[idx][2]]
           end
          idx+=1;
        end
    end

    controlMatrix = [zeros(Nck[int], numControls) for int in 1:Ni];
    idx = 1;
    for int in 1:Ni
        for ctr in 1:numControls
            if numControls > 1
              controlMatrix[int][:,ctr] = decisionVector[controlIdx_all[idx][1]:controlIdx_all[idx][2]];
            else
              controlMatrix[int][:,ctr] = decisionVector[controlIdx[idx][1]:controlIdx[idx][2]];
            end
            idx+=1;
        end
    end
    @pack ps = t0, tf, stateMatrix, controlMatrix
end
