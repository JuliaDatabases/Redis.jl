import Base.connect, Base.TcpSocket, Base.StatusActive, Base.StatusOpen

abstract RedisConnectionBase
abstract SubscribableConnection <: RedisConnectionBase

immutable RedisConnection <: SubscribableConnection
    host::String
    port::Integer
    password::String
    db::Integer
    socket::TcpSocket
end

immutable SentinelConnection <: SubscribableConnection
    host::String
    port::Integer
    password::String
    db::Integer
    socket::TcpSocket
end

immutable TransactionConnection <: RedisConnectionBase
    host::String
    port::Integer
    password::String
    db::Integer
    socket::TcpSocket
end

immutable SubscriptionConnection <: RedisConnectionBase
    host::String
    port::Integer
    password::String
    db::Integer
    callbacks::Dict{String, Function}
    pcallbacks::Dict{String, Function}
    socket::TcpSocket
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

function SubscriptionConnection(parent::SubscribableConnection)
    try
        socket = connect(parent.host, parent.port)
        subscription_connection = SubscriptionConnection(parent.host,
            parent.port, parent.password, parent.db, Dict{String, Function}(),
            Dict{String, Function}(), socket)
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
    conn.socket.status == StatusActive || conn.socket.status == StatusOpen
end

function send_command(conn::RedisConnectionBase, command::String)
    write(conn.socket, command)
end

function execute_command(conn::RedisConnectionBase, command)
    is_connected(conn) || throw(ConnectionException("Socket is disconnected"))
    send_command(conn, pack_command(command))
    reply = parse_reply(readavailable(conn.socket))
    reply.response
end
