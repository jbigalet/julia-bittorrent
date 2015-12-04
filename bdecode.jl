module BDecode

# works with byte array, to support UTF8
function extract_string(s)
    i = search(s,':')
    n = parse(Int, s[1:i-1])
    f = s[i+1:end]
    return f[1:n], f[n+1:end]
end

function extract_int(s)
    i,f = split(s,'e',limit=2)
    return parse(Int, i), f
end

function extract_list(s)
    list = []
    el,f = extract_element(s)
    while(el != nothing)
        push!(list, el)
        el,f = extract_element(f)
    end
    return list, f
end

function extract_dict(s)
    dict = Dict{String,Any}()
    k,f = extract_element(s)
    while(k != nothing)
        v,f = extract_element(f)
        dict[k] = v
        k,f = extract_element(f)
    end
    return dict, f
end

function extract_element(s)
    if length(s) == 0
        return nothing
    elseif s[1] == 'i'
        return extract_int(s[2:end])
    elseif s[1] == 'l'
        return extract_list(s[2:end])
    elseif s[1] == 'd'
        return extract_dict(s[2:end])
    elseif s[1] == 'e'
        return nothing, s[2:end]
    else
        return extract_string(s)
    end
end

bdecode(s) = extract_element(s)[1]

end
