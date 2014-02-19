import Base.push!

const name_map =
    {
     "numel" => "length",
     "zeros" => "matlab_zeros",
     "bsxfun" => "broadcast",
     "max" => "maximum",
     "plus" => "+",
     "@rdivide" => "/",
     "@minus" => "-",
     "~=" => "!=",
     }

const nesting_map =
    {
     "[" => "]",
     "{" => "}",
     "(" => ")",
     "if" => "end",
     "function" => "end",
     "switch" => "end",
     "while" => "end",
     "try" => "end",
     "for" => "end",
     nothing => "", # this shouldn't ever be called
     }
const nesting_map_keys = keys(nesting_map)

### Utility Functions

mapcat(f, itr) = mapreduce(f, vcat, itr)

function take_while{T}(p::Function, a::Array{T,1})
    r = reverse(a)
    take = T[]
    while !isempty(r) && p(r[end])
        push!(take, pop!(r))
    end
    take, reverse(r)
end

counter_map = Dict()
function genvar(name::String)
    # generates a unique var to avoid name collisions
    if !(name in keys(counter_map))
        counter_map[name] = -1
    end
    counter_map[name] += 1
    "__moonwalk_genvar_$(name)_$(counter_map[name])"
end

### Types

abstract ParseNode

type Comment <: ParseNode
    v::String
end

type ParseString <: ParseNode
    v::String
end

type ParseNumber <: ParseNode
    v::Number
end

type ParseTree <: ParseNode
    t
    v::Array{Any, 1}
end
ParseTree(x::String) = ParseTree(x, {x})
ParseTree(x::Nothing) = ParseTree(x, {})
push!(t::ParseTree, x) = push!(t.v, x)

function previous_index(a::Array, i::Int32)
    while i > 1
        i -= 1
        if !isa(a[i], Comment)
            return i
        end
    end
end

const NOSPACE = Comment("__MOONWALK_NOSPACE__")
const NOSPACE_REGEX = Regex("[ \n]*#"*NOSPACE.v"[ \n]*")

isa_matlab_value(x) = true
isa_matlab_value(x::String) = match(r"^\W*$", x) == nothing

isa_paren_tree(x) = false
isa_paren_tree(x::ParseTree) = x.t == "("

isa_brace_tree(x) = false
isa_brace_tree(x::ParseTree) = x.t == "{"

isa_func_tree(x) = false
isa_func_tree(x::ParseTree) = x.t == "function"

isa_comment(x) = isa(x, Comment)

function convert_parse_tree(p::ParseTree, from, to)
    # only works for standard parse trees (not nothing)
    assert(from in nesting_map_keys)
    assert(p.t == from)
    assert(p.v[1] == from)
    assert(p.v[end] == nesting_map[from])
    new_tree = deepcopy(p)
    new_tree.t = to
    new_tree.v[1] = to
    new_tree.v[end] = nesting_map[to]
    new_tree
end

### Transforms

function parse_strings_and_comments(s::String)
    # Convert comments and strings into Comment and ParseString
    # types
    # FIXME this is really ugly code
    parsed = {}
    index = 1
    state = nothing
    while index <= length(s)
        if state == nothing
            m = match(r"\"|%{|%|'", s[index:end])
            if m == nothing
                push!(parsed, s[index:end])
                break
            else
                state_end = index + m.offset - 2
                state = m.match
                push!(parsed, s[index:state_end])
                index += m.offset + length(m.match) - 1
                if (m.match == "'" &&
                    state_end != 0 &&
                    (match(r"\w", s[state_end:state_end]) != nothing))
                    # need to special case this because single
                    # quote might be for matrix transpose
                    state = nothing
                end
            end
        elseif state == "%{"
            m = match(r"%}", s[index:end])
            if m == nothing
                error("unmatched block comment")
            else
                state_end = index + m.offset - 2
                state = nothing
                push!(parsed, Comment(s[index:state_end]))
                index += m.offset + length(m.match) - 1
            end
        elseif state == "%"
            m = match(r"\n", s[index:end])
            if m == nothing
                break
            else
                state_end = index + m.offset - 2
            end
            state = nothing
            push!(parsed, Comment(s[index:state_end]))
            if m == nothing
                index = length(s)
            else
                index += m.offset + length(m.match) - 1
            end
        else
            # for strings
            m = match(Regex(state), s[index:end])
            if m == nothing
                error("unmatched string")
            else
                state_end = index + m.offset - 2
                state = nothing
                push!(parsed, ParseString(s[index:state_end]))
                index += m.offset + length(m.match) - 1
            end
        end
    end
    # merging strings for matrix transpose
    # TODO might not be necessary
    merged = {}
    s = ""
    for p in parsed
        if isa(p, String)
            s *= p
        else
            if !isempty(s)
                push!(merged, s)
                s = ""
            end
            push!(merged, p)
        end
    end
    if !isempty(s)
        push!(merged, s)
        s = ""
    end
    ## map(x->println(repr(x)), merged)
    merged
end

transform_numbers(n::ParseNode) = {n}
function transform_numbers(s::String)
    # adding a blank space to make it easier
    # for regex
    s = " "*s
    m = match(r"\W(\d|[\.\d]{2,})", s)
    if m == nothing
        {s}
    else
        start_index = m.offset + 1
        # TODO change this for hex, binary, etc.
        m2 = match(r"[\.\d]{2,}|\d", s[start_index:end])
        end_index = start_index + length(m2.match) - 1
        prev_string = s[1:start_index - 1]
        match_string = s[start_index:end_index]
        next_string = s[end_index + 1:end]
        # TODO create a map if variable not initialized
        vcat({prev_string, ParseNumber(parse(match_string))},
             transform_numbers(next_string))
    end
end

transform_dot_indexing(n::ParseNode) = {n}
function transform_dot_indexing(s::String)
    # this transform is to convert Matlab's struct indexing
    # to one that resembles Julia's dict ...
    # transforms to calling a string with parens so that
    # the same logic for transforming matrix indexing can be
    # applited
    m = match(r"\.[A-Za-z]", s)
    if m == nothing
        {s}
    else
        start_index = m.offset + 1
        m2 = match(r"^\w+", s[start_index:end])
        end_index = start_index + length(m2.match) - 1
        prev_string = s[1:m.offset - 1]*"("
        match_string = s[start_index:end_index]
        next_string = ")"*s[end_index + 1:end]
        # TODO create a map if variable not initialized
        vcat({prev_string, ParseString(match_string)},
             transform_dot_indexing(next_string))
    end
end

transform_new_lines(n::ParseNode) = {n}
function transform_new_lines(s::ParseString)
    map(ParseString, transform_new_lines(s.v))
end
function transform_new_lines(s::String)
    {replace(s, r"\.\.\.\n|\\\n", "")}
end

tokenize(n::ParseNode) = {n}
function tokenize(s::String)
    # replace semicolon with newline
    s = replace(s, ";", "\n")
    # inject spaces
    s = replace(s, r"[\[\]\(\){};,\n:]", x->" $x ")
    s = replace(s, r"[\w@]+", x->" $x ")
    # don't split with newline because it may be meaningful
    split(s, [' ', '\t'], 0, false)
end

function to_parse_tree(original_tokens)
    function helper(node_type)
        # takes in node_type and starting index and returns a parse
        # tree as well as the ending index of that tree
        t = ParseTree(node_type)
        while !isempty(tokens)
            token = pop!(tokens)
            if token == nesting_map[node_type]
                push!(t, token)
                break
            elseif token in nesting_map_keys
                push!(t, helper(token))
            else
                push!(t, token)
            end
        end
        t
    end
    tokens = reverse(original_tokens)
    helper(nothing)
end

flatten_tree(s) = {s}
function flatten_tree(parse_tree::ParseTree)
    mapcat(flatten_tree, parse_tree.v)
end

prewalk(x, f) = x
function prewalk(parse_tree::ParseTree, f::Function)
    parse_tree = f(parse_tree)
    for i = 1:length(parse_tree.v)
        parse_tree.v[i] = prewalk(parse_tree.v[i], f)
    end
    parse_tree
end

postwalk(x, f) = x
function postwalk(parse_tree::ParseTree, f::Function)
    for i = 1:length(parse_tree.v)
        parse_tree.v[i] = postwalk(parse_tree.v[i], f)
    end
    f(parse_tree)
end

function transform_switch(parse_tree::ParseTree)
    case_test(s) = "=="
    case_test(p::ParseTree) = p.t == "{" ? "in" : "=="

    if parse_tree.t != "switch"
        return parse_tree
    end
    v = reverse(parse_tree.v)
    @assert pop!(v) == "switch" "head of v != \"switch\""
    switch_value = pop!(v)
    var_name = genvar("switch_val")
    first_case = true

    new_v = {var_name, "=", switch_value, "\n"}
    while !isempty(v)
        elem = pop!(v)
        if elem == "case"
            case_val = pop!(v)
            push!(new_v, first_case ? "if" : "elseif")
            push!(new_v, var_name)
            push!(new_v, case_test(case_val))
            push!(new_v, case_val)
            first_case = false
        elseif elem == "otherwise"
            push!(new_v, "else")
        else
            push!(new_v, elem)
        end
    end
    @assert !first_case "0 case statements found in switch clause"

    # TODO consider converting to "if" ParseTree (if there's
    # any reason to do so
    ParseTree("switch", new_v)
end

function transform_function(parse_tree::ParseTree)
    if parse_tree.t == "function" && parse_tree.v[3] == "="
        println(open("pt.txt", "w"), parse_tree)
        return_value = parse_tree.v[2]
        splice!(parse_tree.v, 2:3)
        last = pop!(parse_tree.v)
        @assert last == "end" "function not ending with `end`"
        push!(parse_tree.v, return_value)
        push!(parse_tree.v, last)
    end
    parse_tree
end

function transform_comma(parse_tree::ParseTree)
    if parse_tree.t == "("
        # don't replace commas, might be for function calls
        return parse_tree
    end
    # matlab [1,2,3] == julia [1;2;3]
    replacement = parse_tree.t == "[" ? " " : "\n"
    # ESS mode requires closing bracket... ]
    for i in 1:length(parse_tree.v)
        if parse_tree.v[i] == ","
            parse_tree.v[i] = replacement
        end
    end
    parse_tree
end

function transform_braces(parse_tree::ParseTree)
    i = 2
    while i <= length(parse_tree.v)
        next_elem = parse_tree.v[i]
        if isa_brace_tree(next_elem)
            prev_idx = previous_index(parse_tree.v, i)
            if (prev_idx != nothing &&
                isa_matlab_value(parse_tree.v[prev_idx]))
                parse_tree.v[i] = convert_parse_tree(next_elem, "{", "[")
                insert!(parse_tree.v, i, NOSPACE)
                i += 1
            end
        end
        i += 1
    end
    parse_tree
end

function transform_function_calls(parse_tree::ParseTree)
    take_pred(x) = isa_comment(x) || isa_matlab_value(x)
    start_index = (parse_tree.t == nothing ? 1 :
                   parse_tree.t == "function" ? 3 :
                   parse_tree.t == "matlab_call" ? 3 :
                   2)
    i = start_index
    while i <= length(parse_tree.v)
        next_elem = parse_tree.v[i]
        if isa_paren_tree(next_elem)
            before = parse_tree.v[(i - 1):-1:start_index]
            prev, rest = take_while(take_pred, before)
            comments, prev = take_while(isa_comment, reverse(prev))
            rest = vcat(reverse(rest), comments)

            if !isempty(prev)
                # if equality operator is to the right, we know that it's indexing
                non_matlabs = take_while(take_pred, parse_tree.v[(i+1):end])[2]
                if !isempty(non_matlabs) && non_matlabs[1] == "="
                    # we know that this is a matrix, thus shouldn't
                    # use matlab_call
                    parse_tree.v[i] = convert_parse_tree(next_elem, "(", "[")
                    insert!(parse_tree.v, i, NOSPACE)
                    # move i one forward because we're inserting an element
                    i += 1
                else
                    next_elem = convert_parse_tree(next_elem, "(", "{")

                    function_call = ParseTree("(", vcat({"("}, prev,
                                                        {",", next_elem, ")"}))
                    matlab_call = ParseTree("matlab_call", {"matlab_call",
                                                            NOSPACE,
                                                            function_call})
                    parse_tree.v = vcat(parse_tree.v[1:(start_index - 1)],
                                        rest,
                                        {matlab_call},
                                        parse_tree.v[i+1:end])
                    # start_index - 1 for keeping
                    # length(rest) for rest
                    # 1 for matlab_call
                    i = start_index + length(rest)
                end
            end
        end
        i += 1
    end
    parse_tree
end

function transform_names(parse_tree::ParseTree)
    for i in 1:length(parse_tree.v)
        for (k, v) in name_map
            if parse_tree.v[i] == k
                parse_tree.v[i] = v
                break
            end
        end
    end
    parse_tree
end

to_julia(s::String) = s
to_julia(p::ParseString) = repr(p.v)
to_julia(p::ParseNumber) = repr(p.v)
function to_julia(c::Comment)
    lines = split(c.v, "\n")
    join(map(x->"#"*x*"\n", lines))
end

function remove_spaces(s::String)
    replace(s, NOSPACE_REGEX, "")
end

### Main Function

function moonwalk(matlab_code)
    text = {matlab_code}
    for transform in [
                      parse_strings_and_comments
                      transform_new_lines
                      transform_numbers
                      transform_dot_indexing
                      ## word_substitute
                      tokenize
                      ]
        text = mapcat(transform, text)
    end
    parse_tree = to_parse_tree(text)

    # TODO put in loop
    parse_tree = prewalk(parse_tree, transform_function)
    println("doo")
    parse_tree = prewalk(parse_tree, transform_comma)
    parse_tree = prewalk(parse_tree, transform_switch)
    parse_tree = prewalk(parse_tree, transform_names)
    parse_tree = prewalk(parse_tree, transform_braces)
    parse_tree = prewalk(parse_tree, transform_function_calls)
    ## println(repr(parse_tree))
    ## println(repr(parse_tree))


    text = flatten_tree(parse_tree)
    # inject spaces in between, since they were removed
    # TODO only add spaces around reserved words? if, else, elseif, end, etc.
    # make this optional though for easier testing...
    # still need spaces in brackets though
    text = mapcat(x-> {x, " "}, text)
    ## map(x->println(repr(to_julia(x))), text)
    remove_spaces("include(\"MoonwalkUtils.jl\")\n"*join(map(to_julia, text)))
end
