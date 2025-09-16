#!/bin/bash

# Deploy and Test CORS-Anywhere Script
# This script gets all proxy IPs from terraform and installs CORS-Anywhere on each one

set -e  # Exit on any error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEY_FILE="$HOME/.ssh/tinyproxy-key"
MANUAL_INSTALL_SCRIPT="$SCRIPT_DIR/manual-install.sh"

echo "🚀 Starting CORS-Anywhere manual installation on all instances..."

# Check if key file exists
if [[ ! -f "$KEY_FILE" ]]; then
    echo "❌ Error: SSH key not found at $KEY_FILE"
    echo "Please make sure your SSH key is located at $KEY_FILE"
    exit 1
fi

# Check if manual install script exists
if [[ ! -f "$MANUAL_INSTALL_SCRIPT" ]]; then
    echo "❌ Error: Manual install script not found at $MANUAL_INSTALL_SCRIPT"
    exit 1
fi

# Get proxy IPs from terraform output
echo "📋 Getting proxy IPs from terraform..."
cd "$SCRIPT_DIR"

# Check if terraform state exists
if [[ ! -f "terraform.tfstate" ]]; then
    echo "❌ Error: No terraform state found. Please run 'terraform apply' first."
    exit 1
fi

# Get the proxy IPs using multiple methods
echo "📋 Getting proxy IPs from terraform..."

# Method 1: Try terraform output
PROXY_IPS=$(terraform output -json proxy_endpoints 2>/dev/null | jq -r '.[]' 2>/dev/null | cut -d':' -f1 2>/dev/null || echo "")

# Method 2: If that fails, try filtering out empty IPs
if [[ -z "$PROXY_IPS" ]]; then
    echo "⚠️  proxy_endpoints contains empty IPs, filtering..."
    PROXY_IPS=$(terraform output -json proxy_endpoints 2>/dev/null | jq -r '.[]' 2>/dev/null | cut -d':' -f1 2>/dev/null | grep -v '^$' || echo "")
fi

# Method 3: If that fails, extract from terraform state
if [[ -z "$PROXY_IPS" ]]; then
    echo "⚠️  Terraform output failed, extracting IPs manually..."
    PROXY_IPS=$(terraform show -json 2>/dev/null | jq -r '.values.root_module.resources[] | select(.type=="aws_instance" and .values.public_ip != null and .values.public_ip != "") | .values.public_ip' 2>/dev/null || echo "")
fi

if [[ -z "$PROXY_IPS" ]]; then
    echo "❌ Error: No proxy IPs found using any method."
    echo "Make sure you have deployed instances with terraform apply."
    echo ""
    echo "🔍 Debugging information:"
    echo "Available terraform outputs:"
    terraform output 2>/dev/null || echo "No outputs available"
    echo ""
    echo "Available instances in state:"
    terraform state list | grep aws_instance || echo "No instances found"
    exit 1
fi

# Convert to array
IPS_ARRAY=($PROXY_IPS)
TOTAL_IPS=${#IPS_ARRAY[@]}

echo "📊 Found $TOTAL_IPS proxy instance(s):"
for i in "${!IPS_ARRAY[@]}"; do
    echo "  $((i+1)). ${IPS_ARRAY[i]}"
done

echo ""
echo "🔧 Starting installation on all proxies..."

# Function to install on a single proxy
install_on_proxy() {
    local ip=$1
    local index=$2
    local total=$3
    
    echo ""
    echo "📦 [$index/$total] Installing CORS-Anywhere on $ip..."
    
    # Test SSH connectivity first
    echo "🔗 Testing SSH connectivity..."
    if ! ssh -i "$KEY_FILE" -o ConnectTimeout=10 -o StrictHostKeyChecking=no ubuntu@"$ip" "echo 'SSH connection successful'" >/dev/null 2>&1; then
        echo "❌ Failed to connect to $ip via SSH"
        return 1
    fi
    
    # Copy the manual install script
    echo "� Copying manual-install.sh to $ip..."
    if ! scp -i "$KEY_FILE" -o StrictHostKeyChecking=no "$MANUAL_INSTALL_SCRIPT" ubuntu@"$ip":~/; then
        echo "❌ Failed to copy script to $ip"
        return 1
    fi
    
    # Run the installation
    echo "⚙️  Running installation on $ip..."
    if ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no ubuntu@"$ip" "chmod +x ~/manual-install.sh && sudo ~/manual-install.sh"; then
        echo "✅ Installation completed on $ip"
        
        # Test the CORS-Anywhere proxy (HTTP proxy mode)
        echo "🧪 Testing CORS-Anywhere HTTP proxy $ip:8888..."
        if curl -x "$ip:8888" http://httpbin.org/ip --connect-timeout 10 --max-time 15 >/dev/null 2>&1; then
            echo "✅ CORS-Anywhere HTTP proxy $ip:8888 is working!"
        else
            echo "⚠️  CORS-Anywhere HTTP proxy $ip:8888 test failed"
        fi
        
        # Test CORS mode
        echo "🌐 Testing CORS mode on $ip:8888..."
        if curl "http://$ip:8888/http://httpbin.org/ip" --connect-timeout 10 --max-time 15 >/dev/null 2>&1; then
            echo "✅ CORS mode on $ip:8888 is working!"
        else
            echo "⚠️  CORS mode on $ip:8888 test failed"
        fi
    else
        echo "❌ Installation failed on $ip"
        return 1
    fi
}

# Install on all proxies
SUCCESS_COUNT=0
FAILED_IPS=()

for i in "${!IPS_ARRAY[@]}"; do
    ip="${IPS_ARRAY[i]}"
    index=$((i+1))
    
    if install_on_proxy "$ip" "$index" "$TOTAL_IPS"; then
        ((SUCCESS_COUNT++))
    else
        FAILED_IPS+=("$ip")
    fi
done

echo ""
echo "� Installation Summary:"
echo "  ✅ Successful: $SUCCESS_COUNT/$TOTAL_IPS"
echo "  ❌ Failed: ${#FAILED_IPS[@]}/$TOTAL_IPS"

if [[ ${#FAILED_IPS[@]} -gt 0 ]]; then
    echo ""
    echo "❌ Failed installations:"
    for ip in "${FAILED_IPS[@]}"; do
        echo "  - $ip"
    done
fi

echo ""
echo "🧪 Testing all working proxies..."

# Get successful proxy endpoints
WORKING_PROXIES=()
for ip in "${IPS_ARRAY[@]}"; do
    if [[ ! " ${FAILED_IPS[@]} " =~ " ${ip} " ]]; then
        if curl -x "$ip:8888" http://httpbin.org/ip --connect-timeout 5 --max-time 10 >/dev/null 2>&1; then
            WORKING_PROXIES+=("$ip:8888")
        fi
    fi
done

echo "✅ Working proxies (${#WORKING_PROXIES[@]}/${#IPS_ARRAY[@]}):"
for proxy in "${WORKING_PROXIES[@]}"; do
    echo "  - $proxy"
done

if [[ ${#WORKING_PROXIES[@]} -gt 0 ]]; then
    echo ""
    echo "🎉 Deployment completed! You can use these CORS-Anywhere endpoints:"
    for proxy in "${WORKING_PROXIES[@]}"; do
        echo "  HTTP Proxy: curl -x $proxy http://httpbin.org/ip"
        echo "  CORS Mode:  curl http://$proxy/http://httpbin.org/ip"
    done
    
    # Save working proxies to a file
    printf '%s\n' "${WORKING_PROXIES[@]}" > "$SCRIPT_DIR/working-proxies.txt"
    echo ""
    echo "📄 Working proxies saved to: $SCRIPT_DIR/working-proxies.txt"
else
    echo ""
    echo "❌ No working proxies found. Please check the installation logs."
    exit 1
fi

echo ""
echo "🏁 Script completed!"