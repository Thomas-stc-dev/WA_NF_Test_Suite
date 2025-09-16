#!/bin/bash

# test-proxies.sh
# Script to test all deployed proxy instances

set -e

echo "🧪 Testing TinyProxy instances..."

# Check if terraform output is available
if ! terraform output proxy_endpoints &> /dev/null; then
    echo "❌ No Terraform output found. Make sure you've deployed the infrastructure first."
    exit 1
fi

# Get proxy endpoints
ENDPOINTS=$(terraform output -json proxy_endpoints | jq -r '.[]')

if [ -z "$ENDPOINTS" ]; then
    echo "❌ No proxy endpoints found."
    exit 1
fi

echo "Found $(echo "$ENDPOINTS" | wc -l) proxy instances to test"
echo "=================================="

# Test each proxy
failed_proxies=()
working_proxies=()

for endpoint in $ENDPOINTS; do
    echo "Testing: $endpoint"
    
    # Test with timeout
    if response=$(curl -x "$endpoint" http://httpbin.org/ip --connect-timeout 10 --max-time 15 -s 2>/dev/null); then
        # Extract the origin IP from the response
        origin_ip=$(echo "$response" | jq -r '.origin' 2>/dev/null || echo "unknown")
        echo "✅ $endpoint - Working (Exit IP: $origin_ip)"
        working_proxies+=("$endpoint")
    else
        echo "❌ $endpoint - Failed"
        failed_proxies+=("$endpoint")
    fi
    echo "---"
done

echo "=================================="
echo "📊 Test Summary:"
echo "   ✅ Working: ${#working_proxies[@]}"
echo "   ❌ Failed:  ${#failed_proxies[@]}"
echo "   📍 Total:   $((${#working_proxies[@]} + ${#failed_proxies[@]}))"

if [ ${#working_proxies[@]} -gt 0 ]; then
    echo ""
    echo "✅ Working Proxies:"
    for proxy in "${working_proxies[@]}"; do
        echo "   $proxy"
    done
fi

if [ ${#failed_proxies[@]} -gt 0 ]; then
    echo ""
    echo "❌ Failed Proxies:"
    for proxy in "${failed_proxies[@]}"; do
        echo "   $proxy"
    done
    echo ""
    echo "💡 Failed proxies might be due to:"
    echo "   - Instances still initializing"
    echo "   - Network connectivity issues"
    echo "   - TinyProxy service not started"
    echo ""
    echo "🔧 To troubleshoot, SSH into a failed instance:"
    terraform output ssh_commands | head -5
fi

echo ""
echo "🎯 Example usage with working proxies:"
if [ ${#working_proxies[@]} -gt 0 ]; then
    echo "   curl -x ${working_proxies[0]} https://ipinfo.io"
    echo "   wget -e use_proxy=yes -e http_proxy=${working_proxies[0]} https://httpbin.org/ip"
fi

# Create a simple proxy list file
if [ ${#working_proxies[@]} -gt 0 ]; then
    echo "${working_proxies[@]}" | tr ' ' '\n' > working_proxies.txt
    echo ""
    echo "📝 Working proxies saved to: working_proxies.txt"
fi