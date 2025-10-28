# Special implementations for Redis Cluster multi-key commands
# These commands need special handling because they involve multiple keys
# that may span different slots


const CRC16_TABLE = begin
    table = Vector{UInt16}(undef, 256)
    const poly = 0x1021

    for i = 0:255
        crc = UInt16(i << 8)
        for _ = 1:8
            if (crc & 0x8000) != 0
                crc = (crc << 1) ⊻ poly
            else
                crc = crc << 1
            end
        end
        table[i+1] = crc
    end
    table
end


function crc16(data::Union{AbstractString,AbstractVector{UInt8}}, crc::UInt16 = 0x0000)
    crc_val = crc

    bytes_view = data isa AbstractString ? codeunits(data) : data

    for byte in bytes_view
        table_index = ((crc_val >> 8) ⊻ byte) & 0xFF
        crc_val = ((crc_val << 8) ⊻ CRC16_TABLE[table_index+1]) & 0xFFFF
    end

    return crc_val
end

function calculate_slot(key::Union{AbstractString,AbstractVector{UInt8}})
    local key_for_crc

    # find hash tag '{'
    start_bracket = findfirst(isequal(UInt8('{')), codeunits(key))

    if isnothing(start_bracket)
        key_for_crc = key # no '{', use entire key
    else
        # find in '{' 之后的 '}'
        end_bracket = findnext(isequal(UInt8('}')), codeunits(key), start_bracket + 1)

        # must find both '{' and '}', and there must be content between them
        if !isnothing(end_bracket) && end_bracket > start_bracket + 1
            # only calculate CRC for content between { and }
            # use view or SubString to avoid allocation
            if key isa AbstractString
                key_for_crc = SubString(key, start_bracket + 1, end_bracket - 1)
            else # Vector{UInt8}
                key_for_crc = view(key, (start_bracket+1):(end_bracket-1))
            end
        else
            key_for_crc = key # found '{' but no '}' or {} is empty
        end
    end

    return crc16(key_for_crc) % 16384
end


"""
    keys_in_same_slot(keys...)

Check if all keys are in the same slot.
"""
function keys_in_same_slot(keys...)
    if isempty(keys)
        return true
    end

    first_slot = calculate_slot(keys[1])
    for key in keys[2:end]
        if calculate_slot(key) != first_slot
            return false
        end
    end
    return true
end

# ==================== String Commands ====================

"""
  del(cluster::RedisClusterConnection, keys...)

Delete one or more keys from the cluster.
"""
function del(cluster::RedisClusterConnection, keys...)
    if isempty(keys)
        return execute_command(cluster, ["DEL"])
    end

    slot_map = Dict{Int,Vector{Any}}()
    for key in keys
        slot = calculate_slot(key)
        if !haskey(slot_map, slot)
            slot_map[slot] = []
        end
        push!(slot_map[slot], key)
    end

    if length(slot_map) == 1
        return execute_command(cluster, flatten_command("DEL", keys...))
    end

    total_deleted = 0

    for (slot, keys_in_slot) in slot_map
        try
            command = flatten_command("DEL", keys_in_slot...)
            deleted_count::Integer = execute_command(cluster, command)
            total_deleted += deleted_count
        catch e
            @warn "Failed to DEL keys in slot $slot: $e"
        end
    end

    return total_deleted
end

"""
    mget(cluster::RedisClusterConnection, key, keys...)

Cluster version of MGET - get values of multiple keys.
If keys are in different slots, they are fetched separately and returned in original order.
"""
function mget(cluster::RedisClusterConnection, key, keys...)
    all_keys = [key, keys...]

    # Check if all keys are in the same slot
    if keys_in_same_slot(all_keys...)
        response = execute_command(cluster, flatten_command("MGET", all_keys...))
        return convert_response(Array{Union{AbstractString,Nothing},1}, response)
    end

    # Keys are in different slots, fetch separately
    results = Vector{Union{String,Nothing}}(undef, length(all_keys))
    for (i, k) in enumerate(all_keys)
        results[i] = get(cluster, k)
    end
    return results
end

"""
    mset(cluster::RedisClusterConnection, keyvalues)

Cluster version of MSET - set multiple key-value pairs.
If keys are in different slots, they are set separately.
"""
function mset(cluster::RedisClusterConnection, keyvalues)
    if isa(keyvalues, Dict)
        keys_list = collect(keys(keyvalues))

        # Check if all keys are in the same slot
        if keys_in_same_slot(keys_list...)
            response = execute_command(cluster, flatten_command("MSET", keyvalues))
            return convert_response(Bool, response)
        end

        # Keys are in different slots, set separately
        for (k, v) in keyvalues
            set(cluster, k, v)
        end
        return true
    else
        # Assume array format [key1, val1, key2, val2, ...]
        if length(keyvalues) % 2 != 0
            throw(ClientException("MSET requires an even number of arguments"))
        end

        keys_list = [keyvalues[i] for i = 1:2:length(keyvalues)]

        if keys_in_same_slot(keys_list...)
            response = execute_command(cluster, flatten_command("MSET", keyvalues...))
            return convert_response(Bool, response)
        end

        # Keys are in different slots, set separately
        for i = 1:2:length(keyvalues)
            set(cluster, keyvalues[i], keyvalues[i+1])
        end
        return true
    end
end

"""
    msetnx(cluster::RedisClusterConnection, keyvalues)

Cluster version of MSETNX - set multiple key-value pairs only if all keys don't exist.
Note: In cluster mode, if keys are in different slots, this operation is not atomic.
"""
function msetnx(cluster::RedisClusterConnection, keyvalues)
    if isa(keyvalues, Dict)
        keys_list = collect(keys(keyvalues))

        # Check if all keys are in the same slot
        if keys_in_same_slot(keys_list...)
            response = execute_command(cluster, flatten_command("MSETNX", keyvalues))
            return convert_response(Bool, response)
        end

        # Keys are in different slots - warn about non-atomicity
        @warn "MSETNX with keys in different slots is not atomic in cluster mode"

        # First check if all keys exist
        for k in keys_list
            if exists(cluster, k)
                return false
            end
        end

        # Set all keys
        for (k, v) in keyvalues
            set(cluster, k, v)
        end
        return true
    else
        # Array format
        if length(keyvalues) % 2 != 0
            throw(ClientException("MSETNX requires an even number of arguments"))
        end

        keys_list = [keyvalues[i] for i = 1:2:length(keyvalues)]

        if keys_in_same_slot(keys_list...)
            response = execute_command(cluster, flatten_command("MSETNX", keyvalues...))
            return convert_response(Bool, response)
        end

        @warn "MSETNX with keys in different slots is not atomic in cluster mode"

        for k in keys_list
            if exists(cluster, k)
                return false
            end
        end

        for i = 1:2:length(keyvalues)
            set(cluster, keyvalues[i], keyvalues[i+1])
        end
        return true
    end
end

# ==================== Key Commands ====================

"""
    keys(cluster::RedisClusterConnection, pattern)

Cluster version of KEYS - returns all keys matching the pattern.
Broadcasts the command to all master nodes and aggregates the results.
"""
function keys(cluster::RedisClusterConnection, pattern)
    all_keys = Set{AbstractString}()

    # Broadcast to all master nodes
    for (_, conn) in cluster.node_connections
        try
            node_keys = execute_command(conn, ["KEYS", pattern])
            if node_keys !== nothing
                union!(all_keys, Set(node_keys))
            end
        catch e
            @warn "Failed to execute KEYS on one node: $e"
        end
    end

    return all_keys
end

"""
    randomkey(cluster::RedisClusterConnection)

Cluster version of RANDOMKEY - returns a random key.
Gets a random key from a randomly selected master node.
"""
function randomkey(cluster::RedisClusterConnection)
    if isempty(cluster.node_connections)
        return nothing
    end

    # Select a random master node
    connections = collect(values(cluster.node_connections))
    random_conn = rand(connections)

    response = execute_command(random_conn, ["RANDOMKEY"])
    return convert_response(Union{AbstractString,Nothing}, response)
end

"""
    rename(cluster::RedisClusterConnection, key, newkey)

Cluster version of RENAME.
Note: RENAME requires both keys to be in the same slot.
"""
function rename(cluster::RedisClusterConnection, key, newkey)
    if !keys_in_same_slot(key, newkey)
        throw(
            ClientException(
                "RENAME requires both keys to be in the same slot. Use hash tags like {user}:old and {user}:new",
            ),
        )
    end

    response = execute_command(cluster, flatten_command("RENAME", key, newkey))
    return convert_response(AbstractString, response)
end

"""
    renamenx(cluster::RedisClusterConnection, key, newkey)

Cluster version of RENAMENX.
Note: RENAMENX requires both keys to be in the same slot.
"""
function renamenx(cluster::RedisClusterConnection, key, newkey)
    if !keys_in_same_slot(key, newkey)
        throw(
            ClientException(
                "RENAMENX requires both keys to be in the same slot. Use hash tags like {user}:old and {user}:new",
            ),
        )
    end

    response = execute_command(cluster, flatten_command("RENAMENX", key, newkey))
    return convert_response(Bool, response)
end

# ==================== List Commands ====================

"""
    rpoplpush(cluster::RedisClusterConnection, source, destination)

Cluster version of RPOPLPUSH.
Note: Requires source and destination to be in the same slot.
"""
function rpoplpush(cluster::RedisClusterConnection, source, destination)
    if !keys_in_same_slot(source, destination)
        throw(
            ClientException(
                "RPOPLPUSH requires both keys to be in the same slot. Use hash tags like {list}:source and {list}:dest",
            ),
        )
    end

    response = execute_command(cluster, flatten_command("RPOPLPUSH", source, destination))
    return convert_response(Union{AbstractString,Nothing}, response)
end

"""
    brpoplpush(cluster::RedisClusterConnection, source, destination, timeout)

Cluster version of BRPOPLPUSH.
Note: Requires source and destination to be in the same slot.
"""
function brpoplpush(cluster::RedisClusterConnection, source, destination, timeout)
    if !keys_in_same_slot(source, destination)
        throw(
            ClientException(
                "BRPOPLPUSH requires both keys to be in the same slot. Use hash tags like {list}:source and {list}:dest",
            ),
        )
    end

    response = execute_command(
        cluster,
        flatten_command("BRPOPLPUSH", source, destination, timeout),
    )
    return convert_response(Union{AbstractString,Nothing}, response)
end

# ==================== Set Commands ====================

"""
    smove(cluster::RedisClusterConnection, source, destination, member)

Cluster version of SMOVE.
Note: Requires source and destination to be in the same slot.
"""
function smove(cluster::RedisClusterConnection, source, destination, member)
    if !keys_in_same_slot(source, destination)
        throw(
            ClientException(
                "SMOVE requires both keys to be in the same slot. Use hash tags like {set}:source and {set}:dest",
            ),
        )
    end

    response =
        execute_command(cluster, flatten_command("SMOVE", source, destination, member))
    return convert_response(Bool, response)
end

"""
    sdiff(cluster::RedisClusterConnection, key, keys...)

Cluster version of SDIFF - returns the difference between the first set and other sets.
Note: Requires all keys to be in the same slot.
"""
function sdiff(cluster::RedisClusterConnection, key, keys...)
    all_keys = [key, keys...]

    if !keys_in_same_slot(all_keys...)
        throw(
            ClientException(
                "SDIFF requires all keys to be in the same slot. Use hash tags like {set}:key1 and {set}:key2",
            ),
        )
    end

    response = execute_command(cluster, flatten_command("SDIFF", all_keys...))
    return convert_response(Set{AbstractString}, response)
end

"""
    sinter(cluster::RedisClusterConnection, key, keys...)

Cluster version of SINTER - returns the intersection of all sets.
Note: Requires all keys to be in the same slot.
"""
function sinter(cluster::RedisClusterConnection, key, keys...)
    all_keys = [key, keys...]

    if !keys_in_same_slot(all_keys...)
        throw(
            ClientException(
                "SINTER requires all keys to be in the same slot. Use hash tags like {set}:key1 and {set}:key2",
            ),
        )
    end

    response = execute_command(cluster, flatten_command("SINTER", all_keys...))
    return convert_response(Set{AbstractString}, response)
end

"""
    sunion(cluster::RedisClusterConnection, key, keys...)

Cluster version of SUNION - returns the union of all sets.
Note: Requires all keys to be in the same slot.
"""
function sunion(cluster::RedisClusterConnection, key, keys...)
    all_keys = [key, keys...]

    if !keys_in_same_slot(all_keys...)
        throw(
            ClientException(
                "SUNION requires all keys to be in the same slot. Use hash tags like {set}:key1 and {set}:key2",
            ),
        )
    end

    response = execute_command(cluster, flatten_command("SUNION", all_keys...))
    return convert_response(Set{AbstractString}, response)
end

"""
    sdiffstore(cluster::RedisClusterConnection, destination, key, keys...)

Cluster version of SDIFFSTORE.
Note: Requires all keys to be in the same slot.
"""
function sdiffstore(cluster::RedisClusterConnection, destination, key, keys...)
    all_keys = [destination, key, keys...]

    if !keys_in_same_slot(all_keys...)
        throw(
            ClientException(
                "SDIFFSTORE requires all keys to be in the same slot. Use hash tags",
            ),
        )
    end

    response =
        execute_command(cluster, flatten_command("SDIFFSTORE", destination, key, keys...))
    return convert_response(Integer, response)
end

"""
    sinterstore(cluster::RedisClusterConnection, destination, key, keys...)

Cluster version of SINTERSTORE.
Note: Requires all keys to be in the same slot.
"""
function sinterstore(cluster::RedisClusterConnection, destination, key, keys...)
    all_keys = [destination, key, keys...]

    if !keys_in_same_slot(all_keys...)
        throw(
            ClientException(
                "SINTERSTORE requires all keys to be in the same slot. Use hash tags",
            ),
        )
    end

    response =
        execute_command(cluster, flatten_command("SINTERSTORE", destination, key, keys...))
    return convert_response(Integer, response)
end

"""
    sunionstore(cluster::RedisClusterConnection, destination, key, keys...)

Cluster version of SUNIONSTORE.
Note: Requires all keys to be in the same slot.
"""
function sunionstore(cluster::RedisClusterConnection, destination, key, keys...)
    all_keys = [destination, key, keys...]

    if !keys_in_same_slot(all_keys...)
        throw(
            ClientException(
                "SUNIONSTORE requires all keys to be in the same slot. Use hash tags",
            ),
        )
    end

    response =
        execute_command(cluster, flatten_command("SUNIONSTORE", destination, key, keys...))
    return convert_response(Integer, response)
end

# ==================== HyperLogLog Commands ====================

"""
    pfcount(cluster::RedisClusterConnection, key, keys...)

Cluster version of PFCOUNT.
Note: When using multiple keys, all keys must be in the same slot.
"""
function pfcount(cluster::RedisClusterConnection, key, keys...)
    if isempty(keys)
        # Single key case, execute directly
        response = execute_command(cluster, flatten_command("PFCOUNT", key))
        return convert_response(Integer, response)
    end

    # Multiple keys case
    all_keys = [key, keys...]

    if !keys_in_same_slot(all_keys...)
        throw(
            ClientException(
                "PFCOUNT with multiple keys requires all keys to be in the same slot. Use hash tags",
            ),
        )
    end

    response = execute_command(cluster, flatten_command("PFCOUNT", all_keys...))
    return convert_response(Integer, response)
end

"""
    pfmerge(cluster::RedisClusterConnection, destkey, sourcekey, sourcekeys...)

Cluster version of PFMERGE.
Note: Requires all keys to be in the same slot.
"""
function pfmerge(cluster::RedisClusterConnection, destkey, sourcekey, sourcekeys...)
    all_keys = [destkey, sourcekey, sourcekeys...]

    if !keys_in_same_slot(all_keys...)
        throw(
            ClientException(
                "PFMERGE requires all keys to be in the same slot. Use hash tags",
            ),
        )
    end

    response = execute_command(
        cluster,
        flatten_command("PFMERGE", destkey, sourcekey, sourcekeys...),
    )
    return convert_response(Bool, response)
end

# ==================== Bit Commands ====================

"""
    bitop(cluster::RedisClusterConnection, operation, destkey, key, keys...)

Cluster version of BITOP.
Note: Requires all keys to be in the same slot.
"""
function bitop(cluster::RedisClusterConnection, operation, destkey, key, keys...)
    all_keys = [destkey, key, keys...]

    if !keys_in_same_slot(all_keys...)
        throw(
            ClientException(
                "BITOP requires all keys to be in the same slot. Use hash tags",
            ),
        )
    end

    response =
        execute_command(cluster, flatten_command("BITOP", operation, destkey, key, keys...))
    return convert_response(Integer, response)
end

# ==================== Sorted Set Commands ====================

"""
    zinterstore(cluster::RedisClusterConnection, destination, numkeys, keys, weights=[]; aggregate=Aggregate.NotSet)

Cluster version of ZINTERSTORE.
Note: Requires all keys to be in the same slot.
"""
function zinterstore(
    cluster::RedisClusterConnection,
    destination,
    numkeys,
    keys::Array,
    weights = [];
    aggregate = Aggregate.NotSet,
)

    all_keys = [destination, keys...]

    if !keys_in_same_slot(all_keys...)
        throw(
            ClientException(
                "ZINTERSTORE requires all keys to be in the same slot. Use hash tags",
            ),
        )
    end

    command =
        _build_store_internal(destination, numkeys, keys, weights, aggregate, "zinterstore")
    response = execute_command(cluster, command)
    return convert_response(Integer, response)
end

"""
    zunionstore(cluster::RedisClusterConnection, destination, numkeys, keys, weights=[]; aggregate=Aggregate.NotSet)

Cluster version of ZUNIONSTORE.
Note: Requires all keys to be in the same slot.
"""
function zunionstore(
    cluster::RedisClusterConnection,
    destination,
    numkeys::Integer,
    keys::Array,
    weights = [];
    aggregate = Aggregate.NotSet,
)

    all_keys = [destination, keys...]

    if !keys_in_same_slot(all_keys...)
        throw(
            ClientException(
                "ZUNIONSTORE requires all keys to be in the same slot. Use hash tags",
            ),
        )
    end

    command =
        _build_store_internal(destination, numkeys, keys, weights, aggregate, "zunionstore")
    response = execute_command(cluster, command)
    return convert_response(Integer, response)
end

# ==================== Server Commands ====================

"""
    flushall(cluster::RedisClusterConnection)

Cluster version of FLUSHALL - broadcasts to all master nodes.
Removes all keys from all databases on all nodes in the cluster.
"""
function flushall(cluster::RedisClusterConnection)
    # Broadcast FLUSHALL to all master nodes
    for (_, conn) in cluster.node_connections
        try
            execute_command(conn, ["FLUSHALL"])
        catch e
            @warn "Failed to execute FLUSHALL on node: $e"
        end
    end
    return "OK"
end

"""
    flushdb(cluster::RedisClusterConnection, db::Integer)

Cluster version of FLUSHDB - broadcasts to all master nodes.
Note: In cluster mode, typically only DB 0 is used.
"""
function flushdb(cluster::RedisClusterConnection, db::Integer)
    # Broadcast FLUSHDB to all master nodes
    for (_, conn) in cluster.node_connections
        try
            execute_command(conn, ["FLUSHDB", string(db)])
        catch e
            @warn "Failed to execute FLUSHDB on node: $e"
        end
    end
    return "OK"
end

"""
    _time(cluster::RedisClusterConnection)

Cluster version of TIME - returns time from a random node.
Returns current Unix time from one of the cluster nodes.
"""
function _time(cluster::RedisClusterConnection)
    if isempty(cluster.node_connections)
        throw(ConnectionException("No active connections in cluster"))
    end

    # Get time from a random master node
    connections = collect(values(cluster.node_connections))
    random_conn = rand(connections)

    response = execute_command(random_conn, ["TIME"])
    return convert_response(Array{AbstractString,1}, response)
end

"""
    time(cluster::RedisClusterConnection)

Cluster version of TIME - returns DateTime from a random node.
"""
function time(cluster::RedisClusterConnection)
    t = _time(cluster)
    s = parse(Int, t[1])
    ms = parse(Float64, t[2])
    s += (ms / 1e6)
    return unix2datetime(s)
end

# ==================== Scripting Commands ====================

"""
    evalscript(cluster::RedisClusterConnection, script, numkeys::Integer, keys, args)

Cluster version of EVAL (evalscript).
Routes the script to the node responsible for the first key.
All keys must be in the same slot.
"""
function evalscript(cluster::RedisClusterConnection, script, numkeys::Integer, keys, args)
    # If there are keys, verify they're in the same slot
    if numkeys > 0 && length(keys) > 0
        key_list = keys isa Array ? keys : [keys]
        if length(key_list) > 1 && !keys_in_same_slot(key_list...)
            throw(
                ClientException(
                    "EVAL requires all keys to be in the same slot. Use hash tags",
                ),
            )
        end
        # Route based on first key
        first_key = key_list[1]
        conn = get_connection_for_key(cluster, string(first_key))
        response =
            execute_command(conn, flatten_command("EVAL", script, numkeys, keys, args))
    else
        # No keys - execute on any node
        if !isempty(cluster.node_connections)
            conn = first(values(cluster.node_connections))
            response =
                execute_command(conn, flatten_command("EVAL", script, numkeys, keys, args))
        else
            throw(ConnectionException("No active connections in cluster"))
        end
    end
    return response
end

# ==================== Pub/Sub Commands ====================

"""
    publish(cluster::RedisClusterConnection, channel::AbstractString, message)

Cluster version of PUBLISH.
In Redis Cluster, PUBLISH is broadcast to all nodes in the cluster,
so we can send to any node and it will propagate.
"""
function publish(cluster::RedisClusterConnection, channel::AbstractString, message)
    if isempty(cluster.node_connections)
        throw(ConnectionException("No active connections in cluster"))
    end

    # Publish to any node - it will broadcast to all nodes in the cluster
    conn = first(values(cluster.node_connections))
    response = execute_command(conn, flatten_command("PUBLISH", channel, message))
    return convert_response(Integer, response)
end

"""
    open_subscription(cluster::RedisClusterConnection, err_callback=nothing)

Cluster version of open_subscription.
Creates a subscription connection to one of the cluster nodes.
In Redis Cluster, Pub/Sub messages are automatically broadcast to all nodes,
so subscribing to any single node is sufficient.
"""
function open_subscription(cluster::RedisClusterConnection, err_callback = nothing)
    if isempty(cluster.node_connections)
        throw(ConnectionException("No active connections in cluster"))
    end

    # Select any node for subscription (messages are broadcast across cluster)
    conn = first(values(cluster.node_connections))

    # Use default error callback if none provided
    if err_callback === nothing
        err_callback = err -> @debug err
    end

    # Create subscription connection using the selected node
    s = SubscriptionConnection(conn)
    Threads.@spawn subscription_loop(s, err_callback)
    s
end
