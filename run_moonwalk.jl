#!/bin/env julia

include("moonwalk.jl")

matlab_file = ARGS[1]
print(moonwalk(open(readall, matlab_file)))
