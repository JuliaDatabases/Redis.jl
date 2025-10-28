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

mutable struct RedisClusterConnection <: RedisConnectionBase
    slot_map::Dict{UInt16, RedisConnection}
    startup_nodes::Vector{Tuple{String, Int}}
    password::AbstractString
    db::Integer
    sslconfig::Union{MbedTLS.SSLConfig, Nothing}
    # Node connection pool: (host, port) -> RedisConnection
    node_connections::Dict{Tuple{String, Int}, RedisConnection}
end

Transport.get_sslconfig(s::RedisConnectionBase) = Transport.get_sslconfig(s.transport)
Transport.get_sslconfig(s::RedisClusterConnection) = s.sslconfig

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


# ==================== RedisClusterConnection Methods ====================

"""
    get_node_connection(cluster::RedisClusterConnection, host::String, port::Int) -> RedisConnection

Get or create a connection to the specified cluster node.

This method implements connection pooling for cluster nodes. If a connection
to the specified node already exists and is active, it returns the existing
connection. Otherwise, it creates a new connection.

# Arguments
- `cluster::RedisClusterConnection`: The cluster connection object
- `host::String`: Hostname or IP address of the cluster node
- `port::Int`: Port number of the cluster node

# Returns
- `RedisConnection`: Active connection to the specified node

# Throws
- `ConnectionException`: If unable to establish connection to the node

# Example
```julia
cluster = RedisClusterConnection(startup_nodes=[("127.0.0.1", 7000)])
conn = get_node_connection(cluster, "127.0.0.1", 7001)
```
"""
function get_node_connection(cluster::RedisClusterConnection, host::String, port::Int)
    node_key = (host, port)

    # If connection already exists and is active, return it directly
    if haskey(cluster.node_connections, node_key)
        conn = cluster.node_connections[node_key]
        if is_connected(conn)
            return conn
        else
            # Connection is broken, need to recreate
            delete!(cluster.node_connections, node_key)
        end
    end

    # Create new connection
    try
        conn = RedisConnection(
            host=host,
            port=port,
            password=cluster.password,
            db=cluster.db,
            sslconfig=cluster.sslconfig
        )
        cluster.node_connections[node_key] = conn
        return conn
    catch e
        throw(ConnectionException("Failed to connect to cluster node $host:$port: $e"))
    end
end

"""
    refresh_slot_map!(cluster::RedisClusterConnection)

Refresh the slot mapping information from cluster nodes.

This method queries the Redis Cluster for the current slot distribution
across nodes using the `CLUSTER SLOTS` command. It updates the internal
slot-to-connection mapping to reflect the current cluster topology.

The method attempts to connect to each startup node in sequence until
successful. If all startup nodes fail, it throws a ConnectionException.

# Arguments
- `cluster::RedisClusterConnection`: The cluster connection object

# Throws
- `ConnectionException`: If unable to refresh slot map from any seed node

# Notes
- This method is automatically called during cluster initialization
- It should be called after cluster topology changes (e.g., failover, resharding)
- The method clears existing mappings before building new ones

# Example
```julia
cluster = RedisClusterConnection(startup_nodes=[("127.0.0.1", 7000)])
refresh_slot_map!(cluster)  # Manually refresh if topology changed
```
"""
function refresh_slot_map!(cluster::RedisClusterConnection)
    # Try to get slot information from any available seed node
    local slots_info
    last_error = nothing

    for (host, port) in cluster.startup_nodes
        try
            conn = get_node_connection(cluster, host, port)
            slots_info = execute_command(conn, ["CLUSTER", "SLOTS"])
            break
        catch e
            last_error = e
            @warn "Failed to get cluster slots from $host:$port: $e"
            continue
        end
    end

    if !@isdefined(slots_info)
        throw(ConnectionException("Failed to refresh cluster slot map from any seed node. Last error: $last_error"))
    end

    # Clear existing mappings
    empty!(cluster.slot_map)

    # Parse slot information and build mappings
    # CLUSTER SLOTS returns format: [[start_slot, end_slot, [host, port, node_id], ...], ...]
    for slot_range in slots_info
        start_slot = UInt16(slot_range[1])
        end_slot = UInt16(slot_range[2])

        # Master node information is in the third element
        if length(slot_range) >= 3 && length(slot_range[3]) >= 2
            master_info = slot_range[3]
            host = String(master_info[1])
            port = Int(master_info[2])

            # Get or create connection to this node
            conn = get_node_connection(cluster, host, port)

            # Build mapping for all slots in this range
            for slot in start_slot:end_slot
                cluster.slot_map[slot] = conn
            end
        end
    end

    @info "Refreshed cluster slot map: $(length(cluster.slot_map)) slots mapped to $(length(cluster.node_connections)) nodes"
end

"""
    get_connection_for_slot(cluster::RedisClusterConnection, slot::UInt16) -> RedisConnection

Get the connection corresponding to the specified slot number.

This method looks up which node is responsible for the given slot and
returns the connection to that node. If the slot is not mapped or the
connection is broken, it automatically refreshes the slot mapping.

# Arguments
- `cluster::RedisClusterConnection`: The cluster connection object
- `slot::UInt16`: Slot number (0-16383)

# Returns
- `RedisConnection`: Connection to the node responsible for the slot

# Throws
- `ConnectionException`: If unable to find connection for the slot after refresh

# Example
```julia
cluster = RedisClusterConnection(startup_nodes=[("127.0.0.1", 7000)])
slot = UInt16(1234)
conn = get_connection_for_slot(cluster, slot)
```
"""
function get_connection_for_slot(cluster::RedisClusterConnection, slot::UInt16)
    if haskey(cluster.slot_map, slot)
        conn = cluster.slot_map[slot]
        if is_connected(conn)
            return conn
        end
    end

    # Slot not mapped or connection broken, refresh slot mapping
    refresh_slot_map!(cluster)

    if haskey(cluster.slot_map, slot)
        return cluster.slot_map[slot]
    else
        throw(ConnectionException("Unable to find connection for slot $slot after refresh"))
    end
end

"""
    get_connection_for_key(cluster::RedisClusterConnection, key::Union{AbstractString, AbstractVector{UInt8}}) -> RedisConnection

Get the connection corresponding to the specified key (automatically calculates slot).

This is a convenience method that calculates the hash slot for the given key
and returns the connection to the node responsible for that slot. It supports
hash tags (e.g., `{user:1000}:profile`) for controlling key placement.

# Arguments
- `cluster::RedisClusterConnection`: The cluster connection object
- `key::Union{AbstractString, AbstractVector{UInt8}}`: Redis key

# Returns
- `RedisConnection`: Connection to the node responsible for the key

# Throws
- `ConnectionException`: If unable to find connection for the key's slot

# Example
```julia
cluster = RedisClusterConnection(startup_nodes=[("127.0.0.1", 7000)])
conn = get_connection_for_key(cluster, "user:1000")
conn = get_connection_for_key(cluster, "{user:1000}:profile")  # Hash tag
```
"""
function get_connection_for_key(cluster::RedisClusterConnection, key::Union{AbstractString,AbstractVector{UInt8}})
    slot = calculate_slot(key)
    return get_connection_for_slot(cluster, UInt16(slot))
end

"""
    RedisClusterConnection(; startup_nodes, password="", db=0, sslconfig=nothing) -> RedisClusterConnection

Create a Redis Cluster connection.

This constructor initializes a connection to a Redis Cluster by connecting to
one or more startup nodes and discovering the cluster topology. It automatically
builds an internal mapping of hash slots to cluster nodes.

# Arguments
- `startup_nodes::Vector{Tuple{String, Int}}`: List of seed nodes as [(host, port), ...]
  At least one node must be provided and reachable.
- `password::AbstractString=""`: Authentication password (optional)
- `db::Integer=0`: Database number, typically 0 for cluster mode (optional)
- `sslconfig::Union{MbedTLS.SSLConfig, Nothing}=nothing`: SSL configuration (optional)

# Returns
- `RedisClusterConnection`: Initialized cluster connection object

# Throws
- `ArgumentError`: If startup_nodes is empty
- `ConnectionException`: If unable to initialize cluster connection or refresh slot map

# Notes
- The cluster automatically handles MOVED and ASK redirects
- Slot mapping is refreshed automatically when topology changes are detected
- All node connections share the same password, db, and sslconfig settings
- In cluster mode, only database 0 is typically available

# Example
```julia
# Basic cluster connection
cluster = RedisClusterConnection(
    startup_nodes=[("127.0.0.1", 7000), ("127.0.0.1", 7001), ("127.0.0.1", 7002)]
)

# With authentication
cluster = RedisClusterConnection(
    startup_nodes=[("127.0.0.1", 7000)],
    password="mypassword"
)

# With SSL
cluster = RedisClusterConnection(
    startup_nodes=[("127.0.0.1", 7000)],
    sslconfig=MbedTLS.SSLConfig()
)
```
"""
function RedisClusterConnection(;
    startup_nodes::Vector{Tuple{String,Int}},
    password::AbstractString="",
    db::Integer=0,
    sslconfig::Union{MbedTLS.SSLConfig,Nothing}=nothing
)
    if isempty(startup_nodes)
        throw(ArgumentError("startup_nodes cannot be empty"))
    end

    # Initialize cluster connection object
    cluster = RedisClusterConnection(
        Dict{UInt16,RedisConnection}(),  # slot_map
        startup_nodes,
        password,
        db,
        sslconfig,
        Dict{Tuple{String,Int},RedisConnection}()  # node_connections
    )

    # Initialize slot mapping
    try
        refresh_slot_map!(cluster)
    catch e
        # Clean up any created connections
        for (_, conn) in cluster.node_connections
            try
                disconnect(conn)
            catch
            end
        end
        throw(ConnectionException("Failed to initialize cluster connection: $e"))
    end

    return cluster
end

"""
    disconnect(cluster::RedisClusterConnection)

Disconnect all node connections in the cluster and clean up resources.

This method closes all active connections to cluster nodes and clears
the internal slot mapping and connection pool.

# Arguments
- `cluster::RedisClusterConnection`: The cluster connection to disconnect

# Example
```julia
cluster = RedisClusterConnection(startup_nodes=[("127.0.0.1", 7000)])
# ... use cluster ...
disconnect(cluster)
```
"""
function disconnect(cluster::RedisClusterConnection)
    for (_, conn) in cluster.node_connections
        try
            disconnect(conn)
        catch e
            @warn "Failed to disconnect from node: $e"
        end
    end
    empty!(cluster.node_connections)
    empty!(cluster.slot_map)
end

"""
    is_connected(cluster::RedisClusterConnection) -> Bool

Check if the cluster connection is active.

Returns `true` if at least one node connection in the cluster is active,
`false` otherwise.

# Arguments
- `cluster::RedisClusterConnection`: The cluster connection to check

# Returns
- `Bool`: `true` if at least one node is connected, `false` otherwise

# Example
```julia
cluster = RedisClusterConnection(startup_nodes=[("127.0.0.1", 7000)])
if is_connected(cluster)
    println("Cluster is active")
end
```
"""
function is_connected(cluster::RedisClusterConnection)
    # Consider cluster connected if at least one node connection is active
    for (_, conn) in cluster.node_connections
        if is_connected(conn)
            return true
        end
    end
    return false
end
