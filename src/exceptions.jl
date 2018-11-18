abstract type RedisException<:Exception end

# Thrown if the client is unable to establish a connection to the server
struct ConnectionException <: RedisException
    message::AbstractString
end

# Thrown if the response from the server doesn't conform to RESP
struct ProtocolException <: RedisException
    message::AbstractString
end

# Thrown if the server returns an error response (RESP error)
# merl-dev: removed error_prefix as a separate member, the entire message
# is returned as a single string.  We could parse the message on the first word,
# however, as per http://redis.io/topics/protocol:
#   "This is called an Error Prefix and is a way to allow the client to understand
#   the kind of error returned by the server without to rely on the exact message given,
#   that **may change over the time**.
#   A client implementation may return different kind of exceptions for different
#   errors, or may provide a generic way to trap errors by directly providing the
#   error name to the caller as a string.
#   However, **such a feature should not be considered vital as it is rarely useful**,
#   and a limited client implementation may simply return a generic error condition,
#   such as false.
struct ServerException <: RedisException
    # error_prefix::AbstractString
    message::AbstractString
end

# Thrown if an error originates from the client
struct ClientException <: RedisException
    message::AbstractString
end
