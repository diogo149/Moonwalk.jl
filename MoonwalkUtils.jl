## module MatlabUtils

## export matlab_call, matlab_zeros, matlab_length

matlab_call(A::Function, args...) = A(args...)
matlab_call(A::Any, args...) = A[args...]

matlab_zeros(A::Array) = matlab_zeros(A...)
matlab_zeros(args...) = zeros(args...)

matlab_length(x) = maximum(size(x))

## end
