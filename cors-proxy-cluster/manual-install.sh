#!/bin/bash
# Manual TinyProxy installation script

echo "=== Manual TinyProxy Installation ==="

# Update package list
echo "Updating package list..."
sudo apt update -y

# Install tinyproxy
echo "Installing tinyproxy..."
sudo apt install -y tinyproxy

# Backup original config
echo "Backing up original config..."
sudo cp /etc/tinyproxy/tinyproxy.conf /etc/tinyproxy/tinyproxy.conf.backup

# Create new tinyproxy configuration
echo "Creating new tinyproxy configuration..."
sudo tee /etc/tinyproxy/tinyproxy.conf > /dev/null << 'EOL'
User tinyproxy
Group tinyproxy
Port 8888
Allow 0.0.0.0/0
LogFile "/var/log/tinyproxy/tinyproxy.log"
LogLevel Info
MaxClients 100
MinSpareServers 5
MaxSpareServers 20
StartServers 10
Timeout 600
DefaultErrorFile "/usr/share/tinyproxy/default.html"
StatFile "/usr/share/tinyproxy/stats.html"
ConnectPort 443
ConnectPort 563
ConnectPort 80
ConnectPort 21
ConnectPort 22
ConnectPort 25
ConnectPort 53
ConnectPort 110
ConnectPort 143
ConnectPort 993
ConnectPort 995
DisableViaHeader Yes
Anonymous "Host"
Anonymous "Authorization" 
Anonymous "Cookie"
Anonymous "Referer"
Anonymous "User-Agent"
Anonymous "X-Forwarded-For"
Anonymous "X-Real-IP"
EOL

# Create log directory
echo "Creating log directory..."
sudo mkdir -p /var/log/tinyproxy
sudo chown tinyproxy:tinyproxy /var/log/tinyproxy

# Kill any existing tinyproxy processes
echo "Stopping any existing tinyproxy processes..."
sudo pkill -f tinyproxy || true
sleep 2

# Start tinyproxy directly (bypassing systemd issues)
echo "Starting tinyproxy directly..."
sudo /usr/bin/tinyproxy -c /etc/tinyproxy/tinyproxy.conf

# Also try to enable the service for future reboots
echo "Enabling tinyproxy service..."
sudo systemctl enable tinyproxy || true

# Wait a moment and check status
sleep 3
echo "Checking TinyProxy status..."
sudo systemctl status tinyproxy --no-pager || true

# Test proxy locally (HTTP proxy mode)
echo "Testing HTTP proxy mode locally..."
curl -x localhost:8888 http://httpbin.org/ip --connect-timeout 10 || echo "HTTP proxy test failed"

# Check if tinyproxy process is running
if pgrep -f tinyproxy > /dev/null; then
    echo "✅ TinyProxy is running successfully"
    ps aux | grep tinyproxy | grep -v grep
else
    echo "❌ TinyProxy failed to start"
fi

# Create check script for troubleshooting
cat > /home/ubuntu/check_proxy.sh << 'EOL'
#!/bin/bash
echo "Checking TinyProxy process..."
ps aux | grep tinyproxy | grep -v grep
echo ""
echo "Testing proxy locally..."
curl -x localhost:8888 http://httpbin.org/ip --connect-timeout 10 || echo "Proxy test failed"
EOL

chmod +x /home/ubuntu/check_proxy.sh

echo "=== Installation Complete ==="
echo "TinyProxy should now be running on port 8888"
echo "HTTP Proxy mode: curl -x YOUR_EC2_IP:8888 http://httpbin.org/ip"
echo "Use /home/ubuntu/check_proxy.sh to troubleshoot if needed"
