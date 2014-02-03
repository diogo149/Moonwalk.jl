include("moonwalk.jl")

for filename in split(readall(`ls samples/`))
    m = match(r"(sample\d+)\.m", filename)
    if m != nothing
        sample = m.captures[1]
        prefix = string("samples/", sample)
        matlab_code = open(readall, string(prefix, ".m"))
        julia_code = open(readall, string(prefix, ".jl"))
        julia_code = open(readall, "matlab_utils.jl")*julia_code
        println(prefix)
        transformed = moonwalk(matlab_code)

        same = true

        if transformed != julia_code
            transformed_lines = split(transformed, "\n")
            expected_lines = split(julia_code, "\n")
            diffidx = 1
            while transformed_lines[diffidx] == expected_lines[diffidx]
                diffidx += 1
            end
            println("DIFF LINE ", diffidx)
            println("ACTUAL:")
            println(join(transformed_lines[diffidx:], "\n"))
            println("EXPECTED:")
            println(join(expected_lines[diffidx:], "\n"))
            print(open("transformed.tmp", "w"), transformed)
            print(open("julia_code.tmp", "w"), julia_code)
        end
    end
end
