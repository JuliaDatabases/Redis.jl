#!/bin/bash

HOSTNAME=redisjltest

# Generate self signed root CA cert
openssl req -nodes -x509 -days 3650 -newkey rsa:2048 -keyout ca.key -out ca.crt -subj "/C=IN/ST=KA/L=Bangalore/O=Redisjl/OU=RedisjlTest/CN=${HOSTNAME}/emailAddress=ca@redisjltest.com"

# Generate server cert to be signed
openssl req -nodes -newkey rsa:2048 -keyout server.key -out server.csr -subj "/C=IN/ST=KA/L=Bangalore/O=Redisjl/OU=RedisjlTest/CN=${HOSTNAME}/emailAddress=server@redisjltest.com"

# Sign the server cert
openssl x509 -req -days 3650 -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out server.crt

# Create server PEM file
cat server.key server.crt > server.pem

# Change permissions for mounting inside container
chmod 664 *.key
