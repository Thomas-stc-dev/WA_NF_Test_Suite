const cors_anywhere = require('cors-anywhere');

// CORS Anywhere Server Configuration
const host = process.env.HOST || '0.0.0.0';
const port = process.env.PORT || 8081;

// Configure CORS anywhere
const server = cors_anywhere.createServer({
    // Origins that are allowed to make requests
    originWhitelist: [], // Allow all origins (empty array means no restriction)
    
    // Optional: Restrict to specific origins for security
    // originWhitelist: ['http://localhost:3000', 'https://your-domain.com'],
    
    // Whether to require the special header
    requireHeader: ['origin', 'x-requested-with'],
    
    // Remove these headers from the response
    removeHeaders: ['cookie', 'cookie2'],
    
    // Optional: Add rate limiting
    // httpProxyOptions: {
    //     // xfwd: false, // Disable X-Forwarded-* headers
    // },
    
    // Optional: Custom headers to add to all responses
    setHeaders: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET,HEAD,PUT,PATCH,POST,DELETE',
        'Access-Control-Allow-Headers': 'Origin, X-Requested-With, Content-Type, Accept, Authorization',
    },
});

// Start the server
server.listen(port, host, () => {
    console.log('🚀 CORS Anywhere Server Started');
    console.log('='.repeat(50));
    console.log(`📡 Running on: http://${host}:${port}`);
    console.log(`🌐 Proxy URL format: http://${host}:${port}/TARGET_URL`);
    console.log('='.repeat(50));
    console.log('Examples:');
    console.log(`  http://${host}:${port}/https://api.example.com/data`);
    console.log(`  http://${host}:${port}/http://simulation-amd.waveautoscale.io/api`);
    console.log('='.repeat(50));
    console.log('✅ Ready to proxy requests and add CORS headers!');
});

// Handle graceful shutdown
process.on('SIGINT', () => {
    console.log('\n🛑 Shutting down CORS Anywhere server...');
    server.close(() => {
        console.log('✅ Server closed successfully');
        process.exit(0);
    });
});

// Handle uncaught exceptions
process.on('uncaughtException', (error) => {
    console.error('❌ Uncaught Exception:', error);
    process.exit(1);
});

process.on('unhandledRejection', (reason, promise) => {
    console.error('❌ Unhandled Rejection at:', promise, 'reason:', reason);
    process.exit(1);
});
