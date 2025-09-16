#!/bin/bash
# Manual CORS-Anywhere installation script

echo "=== Manual CORS-Anywhere Installation ==="

# Update package list
echo "Updating package list..."
sudo apt update -y

# Install Node.js (LTS version)
echo "Installing Node.js..."
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
sudo apt install -y nodejs

# Create CORS-Anywhere service directory
echo "Creating service directory..."
sudo mkdir -p /opt/cors-anywhere

# Install CORS-Anywhere locally in the service directory
echo "Installing CORS-Anywhere..."
cd /opt/cors-anywhere
sudo npm init -y
sudo npm install cors-anywhere

# Create CORS-Anywhere service configuration
echo "Creating CORS-Anywhere service configuration..."
sudo tee /opt/cors-anywhere/server.js > /dev/null << 'EOL'
const cors_proxy = require('cors-anywhere');
const host = '0.0.0.0';
const port = 8888;

cors_proxy.createServer({
    originWhitelist: [], // Allow all origins
    requireHeader: [], // No required headers
    removeHeaders: ['cookie', 'cookie2']
}).listen(port, host, function() {
    console.log('CORS-Anywhere proxy running on ' + host + ':' + port);
    console.log('Usage: http://' + host + ':' + port + '/TARGET_URL');
    console.log('Proxy mode: Use this server as HTTP proxy on port ' + port);
});
EOL

# Create systemd service file
echo "Creating systemd service..."
sudo tee /etc/systemd/system/cors-anywhere.service > /dev/null << 'EOL'
[Unit]
Description=CORS-Anywhere Proxy Server
After=network.target

[Service]
Type=simple
User=nobody
WorkingDirectory=/opt/cors-anywhere
ExecStart=/usr/bin/node /opt/cors-anywhere/server.js
Restart=on-failure
RestartSec=5
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=cors-anywhere

[Install]
WantedBy=multi-user.target
EOL

# Create log directory
echo "Creating log directory..."
sudo mkdir -p /var/log/cors-anywhere
sudo chown nobody:nogroup /var/log/cors-anywhere

# Reload systemd and start service
echo "Starting CORS-Anywhere service..."
sudo systemctl daemon-reload
sudo systemctl restart cors-anywhere
sudo systemctl enable cors-anywhere

# Wait a moment and check status
sleep 3
echo "Checking CORS-Anywhere status..."
sudo systemctl status cors-anywhere --no-pager

# Test proxy locally (HTTP proxy mode)
echo "Testing HTTP proxy mode locally..."
curl -x localhost:8888 http://httpbin.org/ip --connect-timeout 10 || echo "HTTP proxy test failed"

# Test CORS mode locally
echo "Testing CORS mode locally..."
curl "http://localhost:8888/http://httpbin.org/ip" --connect-timeout 10 || echo "CORS mode test failed"

echo "=== Installation Complete ==="
echo "CORS-Anywhere should now be running on port 8888"
echo "HTTP Proxy mode: curl -x YOUR_EC2_IP:8888 http://httpbin.org/ip"
echo "CORS mode: curl http://YOUR_EC2_IP:8888/http://httpbin.org/ip"
