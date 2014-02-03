include("moonwalk.jl")

for filename in split(readall(`ls samples/`))
    m = match(r"(sample\d+)\.m", filename)
    if m != nothing
        sample = m.captures[1]
        prefix = string("samples/", sample)
        matlab_code = open(readall, string(prefix, ".m"))
        julia_code = open(readall, string(prefix, ".jl"))
        println(prefix)
        transformed = moonwalk(matlab_code)
        if transformed != julia_code
            println("ACTUAL:")
            println(transformed)
            print(open("transformed.tmp", "w"), transformed)
            println("EXPECTED:")
            println(julia_code)
            print(open("julia_code.tmp", "w"), julia_code)
        end
    end
end
