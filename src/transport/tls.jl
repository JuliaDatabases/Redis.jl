struct TLSTransport <: RedisTransport
    sock::TCPSocket
    ctx::MbedTLS.SSLContext
    sslconfig::MbedTLS.SSLConfig
    buff::IOBuffer

    function TLSTransport(sock::TCPSocket, sslconfig::MbedTLS.SSLConfig)
        ctx = MbedTLS.SSLContext()
        MbedTLS.setup!(ctx, sslconfig)
        MbedTLS.associate!(ctx, sock)
        MbedTLS.handshake(ctx)

        return new(sock, ctx, sslconfig, PipeBuffer())
    end
end

function read_into_buffer_until(cond::Function, t::TLSTransport)
    cond(t) && return

    buff = Vector{UInt8}(undef, MbedTLS.MBEDTLS_SSL_MAX_CONTENT_LEN)
    pbuff = pointer(buff)

    while !cond(t) && !eof(t.ctx)
        nread = readbytes!(t.ctx, buff; all=false)
        if nread > 0
            unsafe_write(t.buff, pbuff, nread)
        end
    end
end

function read_line(t::TLSTransport)
    read_into_buffer_until(t) do t
        iob = t.buff
        (bytesavailable(t.buff) > 0) && (UInt8('\n') in view(iob.data, iob.ptr:iob.size))
    end
    return readline(t.buff)
end
function read_nbytes(t::TLSTransport, m::Int)
    read_into_buffer_until(t) do t
        bytesavailable(t.buff) >= m
    end
    return read(t.buff, m)
end
write_bytes(t::TLSTransport, b::Vector{UInt8}) = write(t.ctx, b)
Base.close(t::TLSTransport) = close(t.ctx)
function set_props!(s::TLSTransport)
    # disable nagle and enable quickack to speed up the usually small exchanges
    Sockets.nagle(s.sock, false)
    Sockets.quickack(s.sock, true)
end
get_sslconfig(t::TLSTransport) = t.sslconfig
io_lock(f, t::TLSTransport) = lock(f, t.sock.lock)
function is_connected(t::TLSTransport)
    status = t.sock.status
    status == StatusActive || status == StatusOpen || status == StatusPaused
end
