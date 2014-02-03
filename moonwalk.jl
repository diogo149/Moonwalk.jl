mapcat(f, itr) = mapreduce(f, vcat, itr)

# why doesn't this work?
## comp(funcs, val) = reduce((v, f) -> f(v), val, funcs)

function thread(funcs, val)
    for func in funcs
        val = func(val)
    end
    val
end

# converts lines to dictionaries to store more information
function line_to_dict(state, line)
    line_dict = {"original" => line, "curr" => line}
end

function dict_to_line(state, line)
    curr = line["curr"]
    if "comment" in keys(line)
        curr *= "#" * line["comment"]
    end
    curr
end

# method for wrapping a function that doesn't rely on
# any state other than the line as a string
function simple_line_transform(f)
    function wrapped(state, line)
        line["curr"] = f(line["curr"])
        [line]
    end
end

function single_line_comment_transform(state, line)
    curr = line["curr"]
    if '%' in curr
        idx = search(curr, '%')
        line["curr"] = curr[1:idx - 1]
        line["comment"] = curr[idx + 1:end]
    end
    [line]
end

function transform_multiline_comments(text)
    function helper(comments)
        without_borders = comments[3:end-2]
        lines = split(without_borders, "\n")
        with_comment = map(x->"%"*x, lines)
        join(with_comment, "\n")
    end
    replace(text, r"%{.*?%}"s, helper)
end

## function transform_singleline_comments(text)
    ## replace(text
## end

function remove_line_continuations(text)
    replace(text, r"\.\.\.\s*", "")
end

const text_transforms =
    [
     transform_multiline_comments
     remove_line_continuations
     ]

# array of functions that takes in global state
# and line state and returns an array of line
# states
const line_transforms =
    [
     line_to_dict
     simple_line_transform(x -> rstrip(x))
     single_line_comment_transform
     dict_to_line
     ]

function moonwalk(matlab_code)
    for transform in text_transforms
        matlab_code = transform(matlab_code)
    end

    global_state = Dict()
    lines = split(matlab_code, "\n")
    for transform in line_transforms
        lines = mapcat(x -> transform(global_state, x), lines)
    end
    join(lines, "\n")
end

"""
Line Schema:
-original: line which this one originated from
-curr: current transformed line
-comment: comment part of the current line

Global State Schema:
-multilinecomment: true if currently in a multiline comment

TODO
-comments
-handle ... line continuations
-function vs indexing syntax
-parse special forms
 -if true 3 else 4 end
 -end
 -etc.
"""
