matlab_call(A::Function, args...) = A(args...)
matlab_call(A::Array, args...) = A[args...]

matlab_zeros(A::Array) = matlab_zeros(A...)
matlab_zeros(args...) = zeros(args...)

### ending matlab_utils, beginning translated code
