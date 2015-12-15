#module yabc

include("bdecode.jl")
include("bencode.jl")
using SHA
using HTTPClient

# poor man's urlencode
hex2url(h) = join(["%$(h[i:i+1])" for i in 1:2:length(h)])

peerid = "jklmfdsqjklmfdsqjklm"
port = 6888

type Torrent
    meta::Dict{AbstractString,Any}
    info_hash::AbstractString
    piece_hashes::Vector{AbstractString}
    tracker_url::AbstractString

    function Torrent(filepath)
        meta = BDecode.bdecode(readall(filepath))
        info_hash = sha1(BEncode.bencode(meta["info"]))

        hexpieces = bytes2hex(convert(Vector{UInt8}, meta["info"]["pieces"]))
        piece_hashes = [hexpieces[i:i+39] for i in 1:40:sizeof(hexpieces)]

        tracker_url = "$(meta["announce"])?info_hash=$(hex2url(info_hash))&peer_id=$(peerid)&port=$(port)&uploaded=0&downloaded=0&left=$(meta["info"]["piece length"])&compact=1&no_peer_id=1&event=started"

        return new(
            meta,
            info_hash,
            piece_hashes,
            tracker_url
        )
    end
end

torrent = Torrent("examples\\archlinux.torrent")
resp = BDecode.bdecode(bytestring(HTTPClient.get(torrent.tracker_url).body))

protocol = "BitTorrent protocol"
protocol_len = bytestring([convert(UInt8, sizeof(protocol))])
handshake =  protocol_len * protocol * "\x00" ^ 8 * bytestring(hex2bytes(torrent.info_hash)) * peerid

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
            [false for i in 1:length(torrent.piece_hashes)]
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
    print(p.conn, handshake)
    Base.wait_readnb(p.conn, 68)
    #assert(nb_available(p) >= 68)
    peer_handshake = readbytes(p.conn, 68)
    assert(bytestring(peer_handshake[1:20]) == protocol_len * protocol) # check protocol
    assert(bytestring(peer_handshake[29:48]) == bytestring(hex2bytes(torrent.info_hash))) # check info_hash
    p.id = bytestring(peer_handshake[49:end])
    return p.id
end

function handlemsg(p::Peer)
    Base.wait_readnb(p.conn, 4)
    len = hton(read(p.conn, Int32))
    
    #keep-alive
    if len == 0
        return "keep-alive"
    end

    Base.wait_readnb(p.conn, 1)
    id = read(p.conn, Int8)

    #choke
    if id == 0
        assert(len == 1)
        p.peer_choking = true
        return "choke"

    #unchoke
    elseif id == 1
        assert(len == 1)
        p.peer_choking = false
        return "unchoke"

    #interested
    elseif id == 2
        assert(len == 1)
        p.peer_interested = true
        return "interested"

    #not interested
    elseif id == 3
        assert(len == 1)
        p.peer_interested = false
        return "not interested"

    #have
    elseif id == 4
        assert(len == 5)
        Base.wait_readnb(p.conn, len-1)
        idx = hton(read(p.conn, Int32))
        assert(idx >= 0 && idx < length(p.have))
        p.have[idx+1] #zero-based index
        return "have $idx"

    #bitfield
    elseif id == 5
        assert(len == 1+ceil(Int, length(p.have)/8))
        Base.wait_readnb(p.conn, len-1)
        for i in 1:len-1
            n = bits(read(p.conn, UInt8))
            for j in 1:8
                idx = 8*(i-1) + j
                if idx <= length(p.have)
                    p.have[idx] = n[j] == '1'
                else
                    assert(n[j] == '0')
                end
            end
        end
        return "bitfield"

    #request
    elseif id == 6
        assert(len == 13)
        index = hton(read(p.conn, Int32))
        offset = hton(read(p.conn, Int32))
        len = hton(read(p.conn, Int32))
        #TODO handle request
        return "request $index @ $offset, size: $len"

    #piece
    elseif id == 7
        #TODO verify size of the block
        index = hton(read(p.conn, Int32))
        offset = hton(read(p.conn, Int32))
        block = readbytes(p.conn, len-9)
        #TODO handle block
        return "piece $index @ $offset"

    #cancel
    elseif id == 8
        assert(len == 13)
        index = hton(read(p.conn, Int32))
        offset = hton(read(p.conn, Int32))
        len = hton(read(p.conn, Int32))
        #TODO handle cancel
        return "cancel $index @ $offset, size: $len"

    #port
    elseif id == 9
        assert(len == 5)
        port = hton(read(p.conn, Int32))
        #TODO handle port switch

    else
        return "unknow =("
    end
end

import Base.send
send(p::Peer, id, payload...)  = write(p.conn, ntoh(Int32(1+ (isempty(payload) ? 0 : sum(sizeof, payload)))), Int8(id), payload...)
keepalive(p::Peer) = write(p.conn, )

choke(p::Peer) = send(p, 0)
unchoke(p::Peer) = send(p, 1)
interested(p::Peer) = send(p, 2)
notinterested(p::Peer) = send(p, 3)
have(p::Peer, index) = send(p, 4, ntoh(Int32(index)))
#bitfield(p::Peer, bitfield) = send(p, 5, bitfield) #TODO
request(p::Peer, index, offset, len = 2^14) = send(p, 6, ntoh(Int32(index)), ntoh(Int32(offset)), ntoh(Int32(len)))
#piece(p::Peer, index, offset, block) = send(p, 7, ntoh(Int32(index)), ntoh(Int32(offset)), block) #TODO
cancel(p::Peer, index, offset, len = 2^14) = send(p, 8, ntoh(Int32(index)), ntoh(Int32(offset)), ntoh(Int32(len)))
updateport(p::Peer, port) = send(p, 9, ntoh(Int32(port)))

testpeer = Peer("192.168.1.86", 51413)
connect(testpeer)

#end
