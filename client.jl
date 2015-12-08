#module yabc

include("bdecode.jl")
include("bencode.jl")
using SHA
using HTTPClient

# poor man's urlencode
hex2url(h) = join(["%$(h[i:i+1])" for i in 1:2:length(h)])

function metainfo(filepath)
    meta = BDecode.bdecode(readall(filepath))
    info_hash = sha1(BEncode.bencode(meta["info"]))
    tracker_url = "$(meta["announce"])?info_hash=$(hex2url(info_hash))&peer_id=jklmfdsqjklmfdsqjklm&port=6888&uploaded=0&downloaded=0&left=$(meta["info"]["piece length"])&compact=1&no_peer_id=1&event=started"
    return Dict{AbstractString,Any}("meta" => meta, "info_hash" => info_hash, "tracker_url" => tracker_url)
end

meta = metainfo("examples\\archlinux.torrent")
resp = BDecode.bdecode(bytestring(HTTPClient.get(meta["tracker_url"]).body))

# parse peers
peers = readbytes(IOBuffer(resp["peers"]))
peerlist = [(peers[i:i+3],peers[i+4:i+5]) for i in 1:6:sizeof(peers)]

#end
