abstract type RedisConnectionBase end
abstract type SubscribableConnection<:RedisConnectionBase end

struct RedisConnection <: SubscribableConnection
    host::AbstractString
    port::Integer
    password::AbstractString
    db::Integer
    transport::Transport.RedisTransport
end

struct SentinelConnection <: SubscribableConnection
    host::AbstractString
    port::Integer
    password::AbstractString
    db::Integer
    transport::Transport.RedisTransport
end

struct TransactionConnection <: RedisConnectionBase
    host::AbstractString
    port::Integer
    password::AbstractString
    db::Integer
    transport::Transport.RedisTransport
end

mutable struct PipelineConnection <: RedisConnectionBase
    host::AbstractString
    port::Integer
    password::AbstractString
    db::Integer
    transport::Transport.RedisTransport
    num_commands::Integer
end

struct SubscriptionConnection <: RedisConnectionBase
    host::AbstractString
    port::Integer
    password::AbstractString
    db::Integer
    callbacks::Dict{AbstractString, Function}
    pcallbacks::Dict{AbstractString, Function}
    transport::Transport.RedisTransport
end

Transport.get_sslconfig(s::RedisConnectionBase) = Transport.get_sslconfig(s.transport)

function RedisConnection(; host="127.0.0.1", port=6379, password="", db=0, sslconfig=nothing)
    try
        connection = RedisConnection(
            host,
            port,
            password,
            db,
            Transport.transport(host, port, sslconfig)
        )
        on_connect(connection)
    catch
        throw(ConnectionException("Failed to connect to Redis server"))
    end
end

function SentinelConnection(; host="127.0.0.1", port=26379, password="", db=0, sslconfig=nothing)
    try
        sentinel_connection = SentinelConnection(
            host,
            port,
            password,
            db,
            Transport.transport(host, port, sslconfig)
        )
        on_connect(sentinel_connection)
    catch
        throw(ConnectionException("Failed to connect to Redis sentinel"))
    end
end

function TransactionConnection(parent::RedisConnection; sslconfig=Transport.get_sslconfig(parent))
    try
        transaction_connection = TransactionConnection(
            parent.host,
            parent.port,
            parent.password,
            parent.db,
            Transport.transport(parent.host, parent.port, sslconfig)
        )
        on_connect(transaction_connection)
    catch
        throw(ConnectionException("Failed to create transaction"))
    end
end

function PipelineConnection(parent::RedisConnection; sslconfig=Transport.get_sslconfig(parent))
    try
        pipeline_connection = PipelineConnection(
            parent.host,
            parent.port,
            parent.password,
            parent.db,
            Transport.transport(parent.host, parent.port, sslconfig),
            0
        )
        on_connect(pipeline_connection)
    catch
        throw(ConnectionException("Failed to create pipeline"))
    end
end

function SubscriptionConnection(parent::SubscribableConnection; sslconfig=Transport.get_sslconfig(parent))
    try
        subscription_connection = SubscriptionConnection(
            parent.host,
            parent.port,
            parent.password,
            parent.db,
            Dict{AbstractString, Function}(),
            Dict{AbstractString, Function}(),
            Transport.transport(parent.host, parent.port, sslconfig)
        )
        on_connect(subscription_connection)
    catch
        throw(ConnectionException("Failed to create subscription"))
    end
end

function on_connect(conn::RedisConnectionBase)
    Transport.set_props!(conn.transport)
    conn.password != "" && auth(conn, conn.password)
    conn.db != 0        && select(conn, conn.db)
    conn
end

function disconnect(conn::RedisConnectionBase)
    Transport.close(conn.transport)
end

function is_connected(conn::RedisConnectionBase)
    Transport.is_connected(conn.transport)
end
