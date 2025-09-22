import * as http from 'http';
import * as https from 'https';
import { URL } from 'url';

// TinyProxy-like HTTP Proxy Server Configuration
const host = process.env.HOST || '0.0.0.0';
const port = process.env.PORT || 8081;

// Create HTTP proxy server
const server = http.createServer();

// Handle HTTP CONNECT method for HTTPS proxying
server.on('connect', (req, clientSocket, head) => {
    const { port: targetPort, hostname } = new URL(`http://${req.url}`);
    
    console.log(`🔒 HTTPS CONNECT request to ${hostname}:${targetPort}`);
    
    // Create connection to target server
    const serverSocket = new (require('net').Socket)();
    
    serverSocket.connect(parseInt(targetPort) || 443, hostname, () => {
        clientSocket.write('HTTP/1.1 200 Connection Established\r\n\r\n');
        serverSocket.write(head);
        serverSocket.pipe(clientSocket);
        clientSocket.pipe(serverSocket);
    });
    
    serverSocket.on('error', (err: Error) => {
        console.error(`❌ HTTPS proxy error for ${hostname}:${targetPort}:`, err.message);
        clientSocket.end();
    });
});

// Handle HTTP requests
server.on('request', (clientReq, clientRes) => {
    const url = new URL(clientReq.url!);
    
    console.log(`🌐 HTTP ${clientReq.method} request to ${url.href}`);
    
    // Prepare options for the target request
    const options = {
        hostname: url.hostname,
        port: url.port || (url.protocol === 'https:' ? 443 : 80),
        path: url.pathname + url.search,
        method: clientReq.method,
        headers: { ...clientReq.headers }
    };
    
    // Remove proxy-related headers
    delete options.headers['proxy-connection'];
    delete options.headers['proxy-authorization'];
    
    // Choose http or https module based on target protocol
    const requestModule = url.protocol === 'https:' ? https : http;
    
    // Make request to target server
    const proxyReq = requestModule.request(options, (proxyRes) => {
        // Copy status and headers from target response
        clientRes.writeHead(proxyRes.statusCode!, proxyRes.headers);
        proxyRes.pipe(clientRes);
    });
    
    // Handle errors
    proxyReq.on('error', (err: Error) => {
        console.error(`❌ HTTP proxy error for ${url.href}:`, err.message);
        clientRes.writeHead(500, { 'Content-Type': 'text/plain' });
        clientRes.end('Proxy Error: ' + err.message);
    });
    
    // Pipe client request to proxy request
    clientReq.pipe(proxyReq);
});

// Handle server errors
server.on('error', (err: Error) => {
    console.error('❌ Proxy server error:', err);
});

// Start the proxy server
server.listen(parseInt(port.toString()), host, () => {
    console.log('🚀 TinyProxy-like HTTP Proxy Server Started');
    console.log('='.repeat(50));
    console.log(`📡 Running on: http://${host}:${port}`);
    console.log(`🔧 Proxy usage: curl -x ${host}:${port} http://example.com`);
    console.log('='.repeat(50));
    console.log('Examples:');
    console.log(`  curl -x ${host}:${port} http://httpbin.org/ip`);
    console.log(`  curl -x ${host}:${port} https://httpbin.org/ip`);
    console.log('='.repeat(50));
    console.log('✅ Ready to proxy HTTP and HTTPS requests!');
});

// Handle graceful shutdown
process.on('SIGINT', () => {
    console.log('\n🛑 Shutting down TinyProxy server...');
    server.close(() => {
        console.log('✅ Server closed');
        process.exit(0);
    });
});

process.on('SIGTERM', () => {
    console.log('\n🛑 Received SIGTERM, shutting down...');
    server.close(() => {
        console.log('✅ Server closed');
        process.exit(0);
    });
});
