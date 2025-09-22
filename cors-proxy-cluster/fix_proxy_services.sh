#!/bin/bash

echo "=== Fixing TinyProxy and CORS-Anywhere Services ==="

# Kill any existing processes
echo "Stopping existing processes..."
sudo pkill -f tinyproxy || true
sudo pkill -f cors-anywhere || true
sleep 2

# Restart TinyProxy service
echo "Starting TinyProxy on port 8888..."
sudo systemctl stop tinyproxy || true
sudo systemctl start tinyproxy || true
sleep 2

# Check TinyProxy status
echo "TinyProxy status:"
sudo systemctl status tinyproxy --no-pager -l || true

# Restart CORS-Anywhere service  
echo "Starting CORS-Anywhere on port 8889..."
sudo systemctl restart cors-anywhere
sleep 2

# Check CORS-Anywhere status
echo "CORS-Anywhere status:"
sudo systemctl status cors-anywhere --no-pager -l || true

# Check ports
echo "=== Port Status ==="
sudo ss -tlnp | grep -E '8888|8889'

# Test both services locally
echo "=== Testing Services ==="
echo "Testing TinyProxy (port 8888):"
curl -x localhost:8888 http://httpbin.org/ip --connect-timeout 5 --max-time 10 || echo "TinyProxy test failed"

echo "Testing CORS-Anywhere (port 8889):"
curl "http://localhost:8889/http://httpbin.org/ip" --connect-timeout 5 --max-time 10 || echo "CORS-Anywhere test failed"

echo "=== Setup Complete ==="
