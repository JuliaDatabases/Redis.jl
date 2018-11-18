import Base.connect, Base.TCPSocket, Base.StatusActive, Base.StatusOpen, Base.StatusPaused

abstract type RedisConnectionBase end
abstract type SubscribableConnection<:RedisConnectionBase end

struct RedisConnection <: SubscribableConnection
    host::AbstractString
    port::Integer
    password::AbstractString
    db::Integer
    socket::TCPSocket
end

struct SentinelConnection <: SubscribableConnection
    host::AbstractString
    port::Integer
    password::AbstractString
    db::Integer
    socket::TCPSocket
end

struct TransactionConnection <: RedisConnectionBase
    host::AbstractString
    port::Integer
    password::AbstractString
    db::Integer
    socket::TCPSocket
end

struct PipelineConnection <: RedisConnectionBase
    host::AbstractString
    port::Integer
    password::AbstractString
    db::Integer
    socket::TCPSocket
    num_commands::Integer
end

struct SubscriptionConnection <: RedisConnectionBase
    host::AbstractString
    port::Integer
    password::AbstractString
    db::Integer
    callbacks::Dict{AbstractString, Function}
    pcallbacks::Dict{AbstractString, Function}
    socket::TCPSocket
end

function RedisConnection(; host="127.0.0.1", port=6379, password="", db=0)
    try
        socket = connect(host, port)
        connection = RedisConnection(host, port, password, db, socket)
        on_connect(connection)
    catch
        throw(ConnectionException("Failed to connect to Redis server"))
    end
end

function SentinelConnection(; host="127.0.0.1", port=26379, password="", db=0)
    try
        socket = connect(host, port)
        sentinel_connection = SentinelConnection(host, port, password, db, socket)
        on_connect(sentinel_connection)
    catch
        throw(ConnectionException("Failed to connect to Redis sentinel"))
    end
end

function TransactionConnection(parent::RedisConnection)
    try
        socket = connect(parent.host, parent.port)
        transaction_connection = TransactionConnection(parent.host,
            parent.port, parent.password, parent.db, socket)
        on_connect(transaction_connection)
    catch
        throw(ConnectionException("Failed to create transaction"))
    end
end

function PipelineConnection(parent::RedisConnection)
    try
        socket = connect(parent.host, parent.port)
        pipeline_connection = PipelineConnection(parent.host,
            parent.port, parent.password, parent.db, socket, 0)
        on_connect(pipeline_connection)
    catch
        throw(ConnectionException("Failed to create pipeline"))
    end
end

function SubscriptionConnection(parent::SubscribableConnection)
    try
        socket = connect(parent.host, parent.port)
        subscription_connection = SubscriptionConnection(parent.host,
            parent.port, parent.password, parent.db, Dict{AbstractString, Function}(),
            Dict{AbstractString, Function}(), socket)
        on_connect(subscription_connection)
    catch
        throw(ConnectionException("Failed to create subscription"))
    end
end

function on_connect(conn::RedisConnectionBase)
    conn.password != "" && auth(conn, conn.password)
    conn.db != 0        && select(conn, conn.db)
    conn
end

function disconnect(conn::RedisConnectionBase)
    close(conn.socket)
end

function is_connected(conn::RedisConnectionBase)
    conn.socket.status == StatusActive || conn.socket.status == StatusOpen || conn.socket.status == StatusPaused
end

function send_command(conn::RedisConnectionBase, command::AbstractString)
    write(conn.socket, command)
end
