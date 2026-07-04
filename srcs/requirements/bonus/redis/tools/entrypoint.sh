#!/bin/bash
set -e

sed -i 's/^bind .*/bind 0.0.0.0/' /etc/redis/redis.conf
sed -i 's/^protected-mode .*/protected-mode no/' /etc/redis/redis.conf
sed -i 's/^daemonize .*/daemonize no/' /etc/redis/redis.conf

exec redis-server /etc/redis/redis.conf
