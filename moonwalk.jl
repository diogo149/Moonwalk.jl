mapcat(f, itr) = mapreduce(f, vcat, itr)

# why doesn't this work?
## comp(funcs, val) = reduce((v, f) -> f(v), val, funcs)

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

function matlab_parentheses_transform(state, line)
    # trying to capture the function/matrix being called
    # won't work for inner parentheses or brackets in either the
    # function/matrix or arguments
    REGEX = r"([\w(\[.*?\])(\(.*?\))]+)\((.*?)\)"
    function helper(s)
        m = match(REGEX, s)
        "matlab_call("*m.captures[1]*", "*m.captures[end]*")"
    end
    # FIXME this won't worked for inner parentheses
    # TODO make sure assumptions hold
    line["curr"] = replace(line["curr"], REGEX, helper)
    line
end

function multiline_comments(text)
    function helper(comments)
        without_borders = comments[3:end-2]
        lines = split(without_borders, "\n")
        with_comment = map(x->"%"*x, lines)
        join(with_comment, "\n")
    end
    replace(text, r"%{.*?%}"s, helper)
end

function remove_line_continuations(text)
    replace(text, r"\.\.\.\s*", "")
end

function double_quote_strings(text)
    replace(text, "'", "\"")
end

function braces_indexing(text)
    function helper(indexing)
        indexing[1:1]*"["*indexing[3:end-1]*"]"
    end
    # this may not work if there are nested braces
    # within the indexing
    # TODO create a map if variable not initialized
    replace(text, r"\w{.*?}"s, helper)
end

function struct_to_map(text)
    function helper(indexing)
        "[\""*indexing[2:end]*"\"]"
    end
    # assumes all dot indexing is for structs
    # TODO create a map if variable not initialized
    replace(text, r"\.[A-z]\w*", helper)
end

const func_map =
    {
     "numel" => "length",
     "zeros" => "matlab_zeros",
     }

function function_replace(text)
    function helper(matched, new_func)
        matched[1:1]*new_func*matched[end:end]
    end

    for (k,v) in func_map
        text = replace(text, Regex("\\W"*k*"\\("), x->helper(x, v))
    end
    text
end

function single_function_file(text)
    # FIXME this relies on some pretty big assumptions on the structure
    # of the file (the last end is the one corresponding to closing
    # the function)
    m = match(r"^function\s+(.+?)\s*=\s*(.*)end\s*$"ms, text)
    if m == nothing
        return text
    end
    "function "*m.captures[2]*m.captures[1]*"\nend\n"
end

const text_transforms =
    [
     multiline_comments
     remove_line_continuations
     double_quote_strings
     braces_indexing
     struct_to_map
     function_replace
     single_function_file
     ]

# array of functions that takes in global state
# and line state and returns an array of line
# states
const line_transforms =
    [
     line_to_dict
     ## simple_line_transform(x -> rstrip(x))
     single_line_comment_transform
     ## matlab_parentheses_transform # TODO need to use real parser, not regex
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
    # TODO change to using a package
    open(readall, "matlab_utils.jl")*join(lines, "\n")
end

"""
Line Schema:
-original: line which this one originated from
-curr: current transformed line
-comment: comment part of the current line

Global State Schema:

TODO
-transforming function arguments
-function vs indexing syntax
-TODO cell calls \w{}
-case statement

-parse special forms
 -if true 3 else 4 end
 -end
 -etc.
"""
