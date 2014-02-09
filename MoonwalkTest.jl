#!/bin/env julia

include("Moonwalk.jl")

function pop_equal(x, y)
    x, y = reverse(x), reverse(y)
    while !isempty(x) && !isempty(y) && x[end] == y[end]
        pop!(x)
        pop!(y)
    end
    reverse(x), reverse(y)
end

for test_num in 1:int(length(split(readall(`ls samples/`)))/2)
    prefix = string("samples/sample", test_num)
    matlab_code = open(readall, string(prefix, ".m"))
    julia_code = open(readall, string(prefix, ".jl"))
    julia_code = split("include(\"MoonwalkUtils.jl\")\n"*julia_code)
    println(prefix)
    transformed = split(moonwalk(matlab_code))
    if transformed != julia_code
        diff_actual, diff_expected = pop_equal(transformed, julia_code)
        println("ACTUAL:")
        println(repr(diff_actual))
        println("EXPECTED:")
        println(repr(diff_expected))
        print(open("transformed.tmp", "w"), transformed)
        print(open("julia_code.tmp", "w"), julia_code)
        ## break # TODO remove
    end
end
