module BEncode

bencode(s::AbstractString) = "$(sizeof(s)):$s"
bencode(i::Int) = "i$(i)e"
bencode(l::Array) = "l$(join(map(bencode,l)))e"
bencode(d::Dict) = "d$(join(map(x->bencode(x[1])*bencode(x[2]), sort(collect(d), by=x->string(x[1])))))e"

end
