"""
    Transport module for Redis.jl abstractes the connection to the Redis server.

Each transportimplementation must provide the following methods:
- `read_line(t::RedisTransport)`: read one line from the transport, similar to `readline`
- `read_nbytes(t::RedisTransport, m::Int)`: read `m` bytes from the transport, similar to `read`
- `write_bytes(t::RedisTransport, b::Vector{UInt8})`: write bytes to the transport, similar to `write`
- `close(t::RedisTransport)`
- `is_connected(t::RedisTransport)`: whether the transport is connected or not
- `status(t::RedisTransport)`: status of the transport, whether it is connected or not
- `set_props!(t::RedisTransport)`: set any properties required. For example, disable nagle and enable quickack to speed up the usually small exchanges
- `get_sslconfig(t::RedisTransport)`: get the SSL configuration for the transport if applicable
- `io_lock(f, t::RedisTransport)`: lock the transport for IO operations

"""
module Transport

using Sockets
using MbedTLS

import Sockets.connect, Sockets.TCPSocket, Base.StatusActive, Base.StatusOpen, Base.StatusPaused

abstract type RedisTransport end

include("tls.jl")
include("tcp.jl")

function transport(host::AbstractString, port::Integer, sslconfig::Union{MbedTLS.SSLConfig, Nothing}=nothing)
    socket = connect(host, port)
    return (sslconfig !== nothing) ? TLSTransport(socket, sslconfig) : TCPTransport(socket)
end

end # module Transport