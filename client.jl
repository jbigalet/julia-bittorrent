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
#resp = BDecode.bdecode(bytestring(HTTPClient.get(meta["tracker_url"]).body))

protocol = "BitTorrent protocol"
protocol_len = bytestring(hex2bytes(hex(sizeof(protocol))))
handshake =  protocol_len * protocol * "\x00" ^ 8 * bytestring(hex2bytes(meta["info_hash"])) * peerid

# parse peers
#peers = readbytes(IOBuffer(resp["peers"]))
#peerlist = [(join(map(Int, peers[i:i+3]), '.'), 256*peers[i+4]+peers[i+5]) for i in 1:6:sizeof(peers)]

#testpeer = peerlist[1]

type Peer
    addr::AbstractString
    port::Int
    conn::TCPSocket
    id::AbstractString
    am_choking::Bool
    am_interested::Bool
    peer_choking::Bool
    peer_interested::Bool
    have::Vector{Bool}
    function Peer(addr, port)
        return new(
            addr,
            port,
            TCPSocket(),
            "",
            true,
            false,
            true,
            false,
            [false for i in 1:Int(meta["meta"]["info"]["length"] / meta["meta"]["info"]["piece length"])]
        )
    end
end

import Base.nb_available
function nb_available(p::Peer)
    Base.start_reading(p.conn)
    return nb_available(p.conn)
end

import Base.connect
function connect(p::Peer)
    p.conn = connect(p.addr, p.port)
    println(p.conn, handshake)
    Base.wait_readnb(p.conn, 68)
    #assert(nb_available(p) >= 68)
    peer_handshake = readbytes(p.conn, 68)
    assert(bytestring(peer_handshake[1:20]) == protocol_len * protocol) # check protocol
    assert(bytestring(peer_handshake[29:48]) == bytestring(hex2bytes(meta["info_hash"]))) # check info_hash
    p.id = bytestring(peer_handshake[49:end])
    return p.id
end

function handlemsg(p::Peer)
    Base.wait_readnb(p.conn, 4)
    len = read(c, Int32)
    
    #keep-alive
    if len == 0
        return
    end

    Base.wait_readnb(p.conn, 1)
    id = read(c, Int8)
    
    #choke
    if id == 0
        assert(len == 1)
        p.peer_choking = true

    #unchoke
    elseif id == 1
        assert(len == 1)
        p.peer_choking = false

    #interested
    elseif id == 2
        assert(len == 1)
        p.peer_interested = true

    #not interested
    elseif id == 3
        assert(len == 1)
        p.peer_interested = false

    #have
    elseif id == 4
        Base.wait_readnb(p.conn, len-1)
        idx = read(p.conn, Int32)
        assert(idx >= 0 && idx < length(p.have))
        p.have[idx+1] #zero-based index

    #bitfield
    elseif id == 5
        assert(len == 1+ceil(Int, length(p.have)/8))
        Base.wait_readnb(p.conn, len-1)
        for i in 1:len-1
            n = read(p.conn, Int8)
            for j in 1:8
                idx = 8*(i-1) + 9 - j
                if idx <= length(p.have)
                    p.have[idx] = n%2
                else
                    assert(n%2 == 0)
                end
                n = div(n, 2)
            end
        end

    #request
    elseif id == 6
        return
end


testpeer = Peer("192.168.1.86", 51413)
connect(testpeer)

#end
