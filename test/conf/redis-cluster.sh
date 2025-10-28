#!/bin/bash

# Script to start a Redis cluster with 3 master nodes for testing

SCRIPT_PATH=$(cd "$(dirname "$0")"; pwd)
TEST_PATH=$(dirname "$SCRIPT_PATH")

# Create directories for cluster nodes
mkdir -p "${TEST_PATH}/cluster-data/7000"
mkdir -p "${TEST_PATH}/cluster-data/7001"
mkdir -p "${TEST_PATH}/cluster-data/7002"

# Create minimal cluster configuration for each node
for port in 7000 7001 7002; do
    cat > "${TEST_PATH}/cluster-data/${port}/redis.conf" <<EOF
port ${port}
cluster-enabled yes
cluster-config-file nodes.conf
cluster-node-timeout 5000
appendonly yes
dir /data
EOF
done

# Start Redis cluster nodes
docker network create redis-cluster 2>/dev/null || true

for port in 7000 7001 7002; do
    docker run -d --name redis-${port} \
        --hostname redis-${port} \
        --network redis-cluster \
        -p ${port}:${port} \
        -v "${TEST_PATH}/cluster-data/${port}":/data \
        redis:7.2.3-bookworm redis-server /data/redis.conf
done

# Wait for nodes to start
echo "Waiting for Redis nodes to start..."
sleep 5

# Create the cluster
echo "Creating Redis cluster..."
docker run -i --rm --network redis-cluster redis:7.2.3-bookworm redis-cli \
    --cluster create \
    redis-7000:7000 \
    redis-7001:7001 \
    redis-7002:7002 \
    --cluster-replicas 0 \
    --cluster-yes

echo "Redis cluster created successfully!"

# Verify cluster status
docker run -i --rm --network redis-cluster redis:7.2.3-bookworm redis-cli \
    -h redis-7000 -p 7000 cluster info
