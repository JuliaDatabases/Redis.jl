abstract RedisException <: Exception

# Thrown if the client is unable to establish a connection to the server
immutable ConnectionException <: RedisException
    message::AbstractString
end

# Thrown if the response from the server doesn't conform to RESP
immutable ProtocolException <: RedisException
    message::AbstractString
end

# Thrown if the server returns an error response (RESP error)
immutable ServerException <: RedisException
    error_prefix::AbstractString
    message::AbstractString
end

# Thrown if an error originates from the client
immutable ClientException <: RedisException
    message::AbstractString
end
