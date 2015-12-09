#module yabc

include("bdecode.jl")
include("bencode.jl")
using SHA
using HTTPClient

# poor man's urlencode
hex2url(h) = join(["%$(h[i:i+1])" for i in 1:2:length(h)])

peerid = "jklmfdsqjklmfdsqjklm"
port = 6888

function metainfo(filepath)
    meta = BDecode.bdecode(readall(filepath))
    info_hash = sha1(BEncode.bencode(meta["info"]))
    tracker_url = "$(meta["announce"])?info_hash=$(hex2url(info_hash))&peer_id=$(peerid)&port=$(port)&uploaded=0&downloaded=0&left=$(meta["info"]["piece length"])&compact=1&no_peer_id=1&event=started"
    return Dict{AbstractString,Any}("meta" => meta, "info_hash" => info_hash, "tracker_url" => tracker_url)
end

meta = metainfo("examples\\archlinux.torrent")
resp = BDecode.bdecode(bytestring(HTTPClient.get(meta["tracker_url"]).body))

protocol = "BitTorrent protocol"
protocol_len = bytestring(hex2bytes(hex(sizeof(protocol))))
handshake =  protocol_len * protocol * "\x00" ^ 8 * bytestring(hex2bytes(meta["info_hash"])) * peerid

# parse peers
peers = readbytes(IOBuffer(resp["peers"]))
peerlist = [(join(map(Int, peers[i:i+3]), '.'), 256*peers[i+4]+peers[i+5]) for i in 1:6:sizeof(peers)]

#testpeer = peerlist[1]
testpeer = ("192.168.1.86", 51413)

conn = connect(testpeer...)
println(conn, handshake)
peer_handshake = readbytes(conn, 68)
assert(bytestring(peer_handshake[1:20]) == protocol_len * protocol) # check protocol
assert(bytestring(peer_handshake[29:48]) == bytestring(hex2bytes(meta["info_hash"]))) # check info_hash
remote_peerid = bytestring(peer_handshake[49:end])

#end
