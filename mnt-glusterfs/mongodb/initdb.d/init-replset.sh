#!/bin/bash

set -e

echo "Replica set initialization script started..."

# Function to wait for MongoDB to listen on all IPs
wait_for_mongo() {
  echo "Waiting for MongoDB to listen on all IP addresses..."
  until mongosh --quiet --eval "db.runCommand({ ping: 1 })" > /dev/null 2>&1; do
    sleep 0.5
  done
  echo "MongoDB is operational."
}

# Function to initialize the replica set
init_replicaset() {
  echo "Initializing the replica set..."
  until mongosh --quiet --eval "load('/docker-entrypoint-initdb.d/init-replset.js')" > /dev/null 2>&1; do
    echo "Initialization failed, retrying in 2 seconds..."
    sleep 2
  done
  echo "Replica set successfully initialized."
}

# Verify that the JS script is available
if [ ! -f "/docker-entrypoint-initdb.d/init-replset.js" ]; then
  echo "Error: init-replset.js file not found in /docker-entrypoint-initdb.d/"
  exit 1
fi

# Steps
wait_for_mongo
init_replicaset

echo "Initialization script completed."
