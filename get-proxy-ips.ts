import { HttpsProxyAgent } from 'https-proxy-agent';
import fetch from 'node-fetch';

interface ProxyInfo {
  ip: string;
  port: number;
  protocol: string;
  country?: string;
  anonymity?: string;
  response_time?: number;
}

interface WorkingProxy {
  proxy: string; // Format for Puppeteer: "ip:port"
  response_time: number;
  country?: string;
  validated: boolean;
}

/**
 * Fetches proxy list from a given URL and returns working HTTP proxies
 * @param proxyListUrl - URL to fetch proxy list from
 * @param maxConcurrentTests - Maximum number of concurrent proxy tests (default: 10)
 * @param timeoutMs - Timeout for proxy validation in milliseconds (default: 10000)
 * @returns Promise<WorkingProxy[]> - Array of working proxies formatted for Puppeteer
 */
export async function getWorkingProxies(
  proxyListUrl: string = 'https://api.proxyscrape.com/v2/?request=get&protocol=http&timeout=10000&country=all&ssl=all&anonymity=all',
  maxConcurrentTests: number = 10,
  timeoutMs: number = 10000
): Promise<WorkingProxy[]> {
  console.log('🔍 Fetching proxy list...');
  
  try {
    // Fetch proxy list
    const response = await fetch(proxyListUrl);
    if (!response.ok) {
      throw new Error(`Failed to fetch proxy list: ${response.status} ${response.statusText}`);
    }
    
    const data = await response.text();
    const proxies = parseProxyList(data);
    
    console.log(`📋 Found ${proxies.length} potential proxies`);
    
    // Filter only HTTP proxies
    const httpProxies = proxies.filter(proxy => 
      proxy.protocol.toLowerCase() === 'http' || 
      proxy.protocol.toLowerCase() === 'https' ||
      !proxy.protocol // If no protocol specified, assume HTTP
    );
    
    console.log(`🔗 Filtered to ${httpProxies.length} HTTP/HTTPS proxies`);
    
    if (httpProxies.length === 0) {
      console.warn('⚠️ No HTTP proxies found in the list');
      return [];
    }
    
    // Validate proxies in batches
    console.log('🧪 Testing proxy connectivity...');
    const workingProxies = await validateProxies(httpProxies, maxConcurrentTests, timeoutMs);
    
    console.log(`✅ Found ${workingProxies.length} working proxies`);
    return workingProxies;
    
  } catch (error) {
    console.error('❌ Error fetching proxies:', error);
    throw error;
  }
}

/**
 * Parses proxy list from various formats
 */
function parseProxyList(data: string): ProxyInfo[] {
  const proxies: ProxyInfo[] = [];
  const lines = data.split('\n').filter(line => line.trim());
  
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    
    try {
      // Try to parse as JSON first (some APIs return JSON)
      if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
        const jsonData = JSON.parse(data);
        if (Array.isArray(jsonData)) {
          return jsonData.map(item => ({
            ip: item.ip || item.host,
            port: parseInt(item.port),
            protocol: item.protocol || 'http',
            country: item.country,
            anonymity: item.anonymity,
            response_time: item.response_time
          })).filter(proxy => proxy.ip && proxy.port);
        }
      }
      
      // Parse common formats: ip:port, ip:port:protocol, etc.
      const parts = trimmed.split(':');
      if (parts.length >= 2 && parts[0] && parts[1]) {
        const ip = parts[0].trim();
        const port = parseInt(parts[1].trim());
        const protocol = parts.length > 2 && parts[2] ? parts[2].trim() : 'http';
        
        if (isValidIP(ip) && !isNaN(port) && port > 0 && port < 65536) {
          proxies.push({
            ip,
            port,
            protocol: protocol.toLowerCase()
          });
        }
      }
    } catch (parseError) {
      // Continue parsing other lines if one fails
      continue;
    }
  }
  
  return proxies;
}

/**
 * Validates if an IP address is in correct format
 */
function isValidIP(ip: string): boolean {
  const ipv4Regex = /^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$/;
  return ipv4Regex.test(ip);
}

/**
 * Validates proxies by testing them with actual HTTP requests and Puppeteer
 */
async function validateProxies(
  proxies: ProxyInfo[], 
  maxConcurrent: number, 
  timeoutMs: number
): Promise<WorkingProxy[]> {
  const workingProxies: WorkingProxy[] = [];
  const testUrl = 'http://httpbin.org/ip'; // Simple endpoint to test proxy connectivity
  
  console.log('🧪 Phase 1: Testing HTTP connectivity...');
  
  // Phase 1: Basic HTTP connectivity test
  for (let i = 0; i < proxies.length; i += maxConcurrent) {
    const batch = proxies.slice(i, i + maxConcurrent);
    const batchPromises = batch.map(proxy => testProxy(proxy, testUrl, timeoutMs));
    
    const results = await Promise.allSettled(batchPromises);
    
    results.forEach((result, index) => {
      if (result.status === 'fulfilled' && result.value) {
        workingProxies.push(result.value);
        console.log(`✅ HTTP test passed: ${result.value.proxy}`);
      } else {
        const proxy = batch[index];
        if (proxy) {
          console.log(`❌ HTTP test failed: ${proxy.ip}:${proxy.port}`);
        }
      }
    });
    
    // Progress indicator
    const processed = Math.min(i + maxConcurrent, proxies.length);
    console.log(`📊 HTTP Progress: ${processed}/${proxies.length} proxies tested`);
  }
  
  if (workingProxies.length === 0) {
    console.log('❌ No proxies passed HTTP tests');
    return [];
  }
  
  console.log(`🧪 Phase 2: Testing Puppeteer compatibility for ${workingProxies.length} proxies...`);
  
  // Phase 2: Test top working proxies with Puppeteer (test only the fastest 10)
  const topProxies = workingProxies.slice(0, Math.min(10, workingProxies.length));
  const puppeteerValidated: WorkingProxy[] = [];
  
  for (const workingProxy of topProxies) {
    const parts = workingProxy.proxy.split(':');
    if (parts.length !== 2 || !parts[0] || !parts[1]) {
      console.log(`❌ Invalid proxy format: ${workingProxy.proxy}`);
      continue;
    }
    
    const proxyInfo: ProxyInfo = {
      ip: parts[0],
      port: parseInt(parts[1]),
      protocol: 'http'
    };
    
    console.log(`🎭 Testing ${workingProxy.proxy} with Puppeteer...`);
    const puppeteerResult = await testProxyWithPuppeteer(proxyInfo);
    
    if (puppeteerResult) {
      puppeteerValidated.push({
        ...workingProxy,
        validated: true
      });
      console.log(`✅ Puppeteer test passed: ${workingProxy.proxy}`);
    } else {
      console.log(`❌ Puppeteer test failed: ${workingProxy.proxy}`);
    }
  }
  
  console.log(`🎯 Final result: ${puppeteerValidated.length} proxies passed both HTTP and Puppeteer tests`);
  
  // If no proxies pass Puppeteer test, return the HTTP-validated ones with a warning
  if (puppeteerValidated.length === 0) {
    console.log('⚠️ No proxies passed Puppeteer validation. Returning HTTP-validated proxies with warning.');
    return workingProxies.map(proxy => ({ ...proxy, validated: false }));
  }
  
  return puppeteerValidated.sort((a, b) => a.response_time - b.response_time);
}

/**
 * Tests a single proxy by making HTTP requests through it to multiple endpoints
 */
async function testProxy(proxy: ProxyInfo, testUrl: string, timeoutMs: number): Promise<WorkingProxy | null> {
  const proxyUrl = `http://${proxy.ip}:${proxy.port}`;
  const startTime = Date.now();
  
  // Test multiple endpoints to ensure proxy works reliably
  const testUrls = [
    'http://httpbin.org/ip',
    'http://httpbin.org/user-agent',
    'https://api.ipify.org?format=json',
    'http://www.google.com/generate_204' // Google's connectivity check
  ];
  
  try {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), timeoutMs);
    
    // Create proxy agent
    const agent = new HttpsProxyAgent(proxyUrl);
    
    let successfulTests = 0;
    const totalTests = testUrls.length;
    
    // Test multiple endpoints
    for (const url of testUrls) {
      try {
        const testController = new AbortController();
        const testTimeoutId = setTimeout(() => testController.abort(), 5000); // 5 second timeout per test
        
        const response = await fetch(url, {
          signal: testController.signal,
          agent: agent as any,
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
          }
        });
        
        clearTimeout(testTimeoutId);
        
        if (response.ok) {
          successfulTests++;
        }
      } catch (testError) {
        // Individual test failed, continue to next
        continue;
      }
    }
    
    clearTimeout(timeoutId);
    
    // Require at least 75% success rate
    const successRate = successfulTests / totalTests;
    if (successRate >= 0.75) {
      const responseTime = Date.now() - startTime;
      return {
        proxy: `${proxy.ip}:${proxy.port}`,
        response_time: responseTime,
        country: proxy.country,
        validated: true
      };
    }
    
    return null;
  } catch (error) {
    return null;
  }
}

/**
 * Alternative validation using HTTP CONNECT method for better proxy testing
 */
async function testProxyWithConnect(proxy: ProxyInfo, timeoutMs: number): Promise<WorkingProxy | null> {
  const startTime = Date.now();
  
  return new Promise((resolve) => {
    const socket = new WebSocket(`ws://${proxy.ip}:${proxy.port}`);
    
    const timeout = setTimeout(() => {
      socket.close();
      resolve(null);
    }, timeoutMs);
    
    socket.onopen = () => {
      clearTimeout(timeout);
      const responseTime = Date.now() - startTime;
      socket.close();
      resolve({
        proxy: `${proxy.ip}:${proxy.port}`,
        response_time: responseTime,
        country: proxy.country,
        validated: true
      });
    };
    
    socket.onerror = () => {
      clearTimeout(timeout);
      socket.close();
      resolve(null);
    };
  });
}

/**
 * Tests proxy specifically with Puppeteer to catch ERR_HTTP_RESPONSE_CODE_FAILURE
 */
async function testProxyWithPuppeteer(proxy: ProxyInfo): Promise<boolean> {
  const puppeteer = require('puppeteer');
  
  try {
    const browser = await puppeteer.launch({
      headless: true,
      args: [
        `--proxy-server=${proxy.ip}:${proxy.port}`,
        '--no-sandbox',
        '--disable-setuid-sandbox',
        '--disable-web-security',
        '--ignore-certificate-errors',
        '--ignore-ssl-errors',
        '--disable-features=VizDisplayCompositor',
        '--timeout=10000'
      ],
    });
    
    const page = await browser.newPage();
    
    // Set a short timeout for this test
    page.setDefaultTimeout(10000);
    
    try {
      // Test with a simple page that should load quickly
      await page.goto('http://httpbin.org/ip', { 
        waitUntil: 'networkidle0',
        timeout: 10000 
      });
      
      // If we get here, the proxy works with Puppeteer
      await browser.close();
      return true;
    } catch (error: any) {
      await browser.close();
      
      // Check for specific Puppeteer/Chromium errors
      if (error.message && (
        error.message.includes('ERR_HTTP_RESPONSE_CODE_FAILURE') ||
        error.message.includes('ERR_PROXY_CONNECTION_FAILED') ||
        error.message.includes('ERR_TUNNEL_CONNECTION_FAILED') ||
        error.message.includes('net::ERR_')
      )) {
        console.log(`❌ Puppeteer proxy test failed for ${proxy.ip}:${proxy.port} - ${error.message}`);
        return false;
      }
      
      return false;
    }
  } catch (error) {
    return false;
  }
}

/**
 * Alternative method to get proxies with better parsing
 */
export async function getProxiesFromFreeProxyList(): Promise<WorkingProxy[]> {
  // Try multiple sources with different formats
  const sources = [
    'https://www.proxy-list.download/api/v1/get?type=http',
    'https://api.proxyscrape.com/v4/free-proxy-list/get?request=display_proxies&protocol=http&proxy_format=protocolipport&format=json&timeout=20',
    'https://raw.githubusercontent.com/TheSpeedX/PROXY-List/master/http.txt'
  ];
  
  for (const source of sources) {
    try {
      console.log(`🔍 Trying source: ${source}`);
      const response = await fetch(source);
      if (!response.ok) continue;
      
      const data = await response.text();
      console.log(`📄 Response preview: ${data.substring(0, 200)}...`);
      
      const proxies = parseProxyListImproved(data);
      if (proxies.length > 0) {
        console.log(`✅ Successfully parsed ${proxies.length} proxies from ${source}`);
        const validatedProxies = await validateProxies(proxies, 5, 5000);
        return validatedProxies;
      }
    } catch (error) {
      console.warn(`⚠️ Failed to get proxies from ${source}:`, error);
    }
  }
  
  return [];
}

/**
 * Improved proxy list parser
 */
function parseProxyListImproved(data: string): ProxyInfo[] {
  const proxies: ProxyInfo[] = [];
  
  // Clean the data and split into lines
  const lines = data
    .replace(/\r/g, '')
    .split('\n')
    .map(line => line.trim())
    .filter(line => line && !line.startsWith('#') && !line.startsWith('//'));
  
  console.log(`📝 Processing ${lines.length} lines of proxy data`);
  
  for (const line of lines) {
    try {
      // Skip empty lines and comments
      if (!line || line.startsWith('#') || line.startsWith('//')) continue;
      
      // Try to match IP:PORT pattern
      const match = line.match(/(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}):(\d{1,5})/);
      if (match && match[1] && match[2]) {
        const ip = match[1];
        const port = parseInt(match[2]);
        
        if (isValidIP(ip) && port > 0 && port < 65536) {
          proxies.push({
            ip,
            port,
            protocol: 'http'
          });
        }
      }
    } catch (error) {
      // Continue parsing other lines
      continue;
    }
  }
  
  console.log(`✅ Successfully parsed ${proxies.length} valid proxies`);
  return proxies;
}

/**
 * Example usage function
 */
export async function example() {
  try {
    // Method 1: Fetch from improved proxy sources
    console.log('🚀 Method 1: Trying improved proxy sources...');
    let proxies = await getProxiesFromFreeProxyList();
    
    // Method 2: If no proxies found, try the original method
    if (proxies.length === 0) {
      console.log('🚀 Method 2: Trying original method...');
      proxies = await getWorkingProxies();
    }
    
    console.log('\n🎯 Working proxies for Puppeteer:');
    proxies.forEach((proxy, index) => {
      console.log(`${index + 1}. ${proxy.proxy} (${proxy.response_time}ms) ${proxy.country || ''} ${proxy.validated ? '✅' : '❓'}`);
    });
    
    // Use with Puppeteer
    if (proxies.length > 0) {
      console.log('\n🚀 Example Puppeteer usage:');
      console.log(`puppeteer.launch({ args: ['--proxy-server=${proxies[0]?.proxy}'] })`);
      
      console.log('\n📋 All proxy strings for Puppeteer:');
      proxies.forEach((proxy, index) => {
        console.log(`  ${index + 1}. --proxy-server=${proxy.proxy}`);
      });
    } else {
      console.log('❌ No working proxies found. You may need to try different sources or check your network connection.');
    }
    
    return proxies;
  } catch (error) {
    console.error('Error:', error);
    return [];
  }
}

/**
 * Get working proxy for Puppeteer with error handling
 */
export async function getRandomWorkingProxy(): Promise<string | null> {
  try {
    const proxies = await getProxiesFromFreeProxyList();
    if (proxies.length === 0) {
      console.warn('⚠️ No working proxies available');
      return null;
    }
    
    // Return a random proxy from the working ones
    const randomProxy = proxies[Math.floor(Math.random() * proxies.length)];
    if (randomProxy) {
      console.log(`🎯 Selected proxy: ${randomProxy.proxy} (${randomProxy.response_time}ms)`);
      return randomProxy.proxy;
    }
    return null;
  } catch (error) {
    console.error('❌ Error getting proxy:', error);
    return null;
  }
}

/**
 * Get proxies specifically validated for Puppeteer usage
 * This function addresses the ERR_HTTP_RESPONSE_CODE_FAILURE issue
 */
export async function getPuppeteerValidatedProxies(count: number = 5): Promise<string[]> {
  console.log('🎭 Getting Puppeteer-validated proxies...');
  
  try {
    const proxies = await getProxiesFromFreeProxyList();
    
    if (proxies.length === 0) {
      console.log('❌ No proxies found from sources');
      return [];
    }
    
    // Filter to only fully validated proxies
    const validatedProxies = proxies.filter(proxy => proxy.validated === true);
    
    if (validatedProxies.length === 0) {
      console.log('⚠️ No proxies passed Puppeteer validation, trying HTTP-validated ones...');
      // Return top HTTP-validated proxies with warning
      return proxies.slice(0, count).map(proxy => proxy.proxy);
    }
    
    console.log(`✅ Found ${validatedProxies.length} Puppeteer-validated proxies`);
    return validatedProxies.slice(0, count).map(proxy => proxy.proxy);
    
  } catch (error) {
    console.error('❌ Error getting Puppeteer-validated proxies:', error);
    return [];
  }
}

/**
 * Get multiple working proxies for rotation (enhanced with Puppeteer validation)
 */
export async function getProxyPool(count: number = 5): Promise<string[]> {
  return await getPuppeteerValidatedProxies(count);
}

// Run example if this file is executed directly
if (import.meta.main) {
  example();
}
