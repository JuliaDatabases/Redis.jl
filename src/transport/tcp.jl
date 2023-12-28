struct TCPTransport <: RedisTransport
    sock::TCPSocket
end

read_line(t::TCPTransport) = readline(t.sock)
read_nbytes(t::TCPTransport, m::Int) = read(t.sock, m)
write_bytes(t::TCPTransport, b::Vector{UInt8}) = write(t.sock, b)
Base.close(t::TCPTransport) = close(t.sock)
function set_props!(t::TCPTransport)
    # disable nagle and enable quickack to speed up the usually small exchanges
    Sockets.nagle(t.sock, false)
    Sockets.quickack(t.sock, true)
end
get_sslconfig(::TCPTransport) = nothing
io_lock(f, t::TCPTransport) = lock(f, t.sock.lock)
function is_connected(t::TCPTransport)
    status = t.sock.status
    status == StatusActive || status == StatusOpen || status == StatusPaused
end
