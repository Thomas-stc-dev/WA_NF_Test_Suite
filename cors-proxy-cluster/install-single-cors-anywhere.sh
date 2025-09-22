#!/bin/bash

# Single instance CORS-Anywhere installer
# Usage: ./install-single-cors-anywhere.sh <IP_ADDRESS>

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SSH_KEY="~/.ssh/tinyproxy-key"
SSH_USER="ubuntu"
SSH_OPTS="-o ConnectTimeout=10 -o StrictHostKeyChecking=no"

# Function to print colored output
print_status() {
    echo -e "${BLUE}📋 $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Check if IP address is provided
if [ $# -eq 0 ]; then
    print_error "Usage: $0 <IP_ADDRESS>"
    echo "Example: $0 13.231.227.118"
    exit 1
fi

TARGET_IP="$1"

# Validate IP format (basic check)
if ! echo "$TARGET_IP" | grep -E '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$' > /dev/null; then
    print_error "Invalid IP address format: $TARGET_IP"
    exit 1
fi

print_status "🚀 Starting CORS-Anywhere installation on $TARGET_IP"

# Test SSH connectivity first
print_status "🔗 Testing SSH connectivity to $TARGET_IP..."
if ! ssh $SSH_OPTS -i "$SSH_KEY" "$SSH_USER@$TARGET_IP" "echo 'SSH connection successful'" 2>/dev/null; then
    print_error "Failed to connect to $TARGET_IP via SSH"
    print_warning "Make sure:"
    echo "  - The instance is running and accessible"
    echo "  - SSH key '$SSH_KEY' exists and has correct permissions"
    echo "  - Security group allows SSH from your IP"
    exit 1
fi

print_success "SSH connection to $TARGET_IP successful"

# Create the installation script
print_status "📦 Creating CORS-Anywhere installation script..."
cat > /tmp/cors_anywhere_install.sh << 'EOF'
#!/bin/bash

set -e

echo "=== Starting CORS-Anywhere installation at $(date) ==="

# Update package list
echo "Updating package list..."
sudo apt-get update -y

# Install Node.js (LTS version)
echo "Installing Node.js..."
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo bash -
sudo apt-get install -y nodejs

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
const port = 8889;

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
StandardOutput=journal
StandardError=journal

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
sudo systemctl enable cors-anywhere
sudo systemctl start cors-anywhere
# Wait for service to start
sleep 5

# Test CORS mode locally
echo "Testing CORS mode locally..."
curl "http://localhost:8889/http://httpbin.org/ip" --connect-timeout 10 --max-time 15 || echo "CORS mode test failed"

# Test HTTP proxy mode locally
echo "Testing HTTP proxy mode locally..."
curl -x localhost:8889 http://httpbin.org/ip --connect-timeout 10 --max-time 15 || echo "HTTP proxy mode test failed"

echo "=== CORS-Anywhere installation completed at $(date) ==="

# Check service status
echo "=== Service Status ==="
sudo systemctl status cors-anywhere --no-pager -l || true

echo "=== Process Status ==="
ps aux | grep cors-anywhere | grep -v grep || echo "No CORS-Anywhere process found"

echo "=== Port Status ==="
sudo ss -tlnp | grep 8889 || echo "Port 8889 not listening"
EOF

# Upload and execute the installation script
print_status "📤 Uploading installation script to $TARGET_IP..."
scp $SSH_OPTS -i "$SSH_KEY" /tmp/cors_anywhere_install.sh "$SSH_USER@$TARGET_IP:/tmp/"

print_status "🔧 Executing installation on $TARGET_IP..."
ssh $SSH_OPTS -i "$SSH_KEY" "$SSH_USER@$TARGET_IP" "chmod +x /tmp/cors_anywhere_install.sh && /tmp/cors_anywhere_install.sh"

# Test the installation
print_status "🧪 Testing CORS-Anywhere installation..."
sleep 5

if curl -s "http://$TARGET_IP:8889/http://httpbin.org/ip" --connect-timeout 10 --max-time 15 > /dev/null; then
    print_success "CORS-Anywhere is working on $TARGET_IP:8889"
    
    # Test both modes
    print_status "Testing CORS mode..."
    CORS_RESULT=$(curl -s "http://$TARGET_IP:8889/http://httpbin.org/ip" --connect-timeout 10 --max-time 15 2>/dev/null || echo "failed")
    if [[ "$CORS_RESULT" != "failed" ]]; then
        print_success "✅ CORS mode working"
        echo "   Test: curl \"http://$TARGET_IP:8889/http://httpbin.org/ip\""
    else
        print_warning "CORS mode test failed"
    fi
    
    print_status "Testing HTTP proxy mode..."
    PROXY_RESULT=$(curl -s -x "$TARGET_IP:8889" "http://httpbin.org/ip" --connect-timeout 10 --max-time 15 2>/dev/null || echo "failed")
    if [[ "$PROXY_RESULT" != "failed" ]]; then
        print_success "✅ HTTP proxy mode working"
        echo "   Test: curl -x \"$TARGET_IP:8889\" \"http://httpbin.org/ip\""
    else
        print_warning "HTTP proxy mode test failed"
    fi
    
else
    print_error "CORS-Anywhere is not responding on $TARGET_IP:8889"
    print_status "Checking service status on remote host..."
    ssh $SSH_OPTS -i "$SSH_KEY" "$SSH_USER@$TARGET_IP" "sudo systemctl status cors-anywhere --no-pager -l || echo 'Service not found'"
fi

# Cleanup
rm -f /tmp/cors_anywhere_install.sh

print_success "🎉 Installation process completed for $TARGET_IP"
print_status "📋 Summary:"
echo "   - Target IP: $TARGET_IP"
echo "   - CORS URL: http://$TARGET_IP:8889/TARGET_URL"
echo "   - Proxy: $TARGET_IP:8889"
echo ""
print_status "🔧 To check status later, run:"
echo "   ssh -i $SSH_KEY $SSH_USER@$TARGET_IP 'sudo systemctl status cors-anywhere'"
