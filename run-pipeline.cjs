#!/usr/bin/env node

const { spawn } = require('child_process');
const path = require('path');

// Configuration
const config = {
    httpServer: {
        command: 'npx',
        args: ['http-server', 'html', '-p', '8080', '--cors'],
        name: '🌐 HTTP Server'
    },
    corsProxy: {
        command: 'bun',
        args: ['tinyproxy.ts'],
        name: '🔗 TinyProxy Server'
    },
    trafficGenerator: {
        command: 'bun',
        args: ['index.ts'],
        name: '🚀 Traffic Generator'
    }
};

// Colors for console output
const colors = {
    reset: '\x1b[0m',
    red: '\x1b[31m',
    green: '\x1b[32m',
    yellow: '\x1b[33m',
    blue: '\x1b[34m',
    magenta: '\x1b[35m',
    cyan: '\x1b[36m'
};

function log(message, color = colors.reset) {
    console.log(`${color}${message}${colors.reset}`);
}

function runCommand(config, stepNumber, totalSteps) {
    return new Promise((resolve, reject) => {
        log(`\n${'='.repeat(60)}`, colors.cyan);
        log(`Step ${stepNumber}/${totalSteps}: Starting ${config.name}`, colors.green);
        log(`Command: ${config.command} ${config.args.join(' ')}`, colors.yellow);
        log(`${'='.repeat(60)}`, colors.cyan);

        const process = spawn(config.command, config.args, {
            stdio: 'inherit',
            shell: true
        });

        process.on('close', (code) => {
            if (code === 0) {
                log(`✅ ${config.name} completed successfully`, colors.green);
                resolve();
            } else if (code === 130) {
                log(`⚠️  ${config.name} interrupted by user (Ctrl+C)`, colors.yellow);
                resolve(); // Continue to next step even if interrupted
            } else {
                log(`❌ ${config.name} failed with exit code ${code}`, colors.red);
                reject(new Error(`${config.name} failed with exit code ${code}`));
            }
        });

        process.on('error', (error) => {
            log(`❌ Failed to start ${config.name}: ${error.message}`, colors.red);
            reject(error);
        });
    });
}

async function runSequentially() {
    log('🚀 Starting Traffic Generator Pipeline', colors.magenta);
    log('Press Ctrl+C to stop current step and move to next', colors.yellow);
    
    const steps = [
        config.httpServer,
        config.corsProxy,
        config.trafficGenerator
    ];

    try {
        for (let i = 0; i < steps.length; i++) {
            await runCommand(steps[i], i + 1, steps.length);
            
            // Add a small delay between steps
            if (i < steps.length - 1) {
                log('⏳ Waiting 2 seconds before next step...', colors.yellow);
                await new Promise(resolve => setTimeout(resolve, 2000));
            }
        }
        
        log('\n🎉 All steps completed successfully!', colors.green);
        log('Pipeline finished.', colors.cyan);
        
    } catch (error) {
        log(`\n💥 Pipeline failed: ${error.message}`, colors.red);
        process.exit(1);
    }
}

// Handle Ctrl+C gracefully
process.on('SIGINT', () => {
    log('\n⚠️  Pipeline interrupted by user', colors.yellow);
    process.exit(0);
});

// Start the pipeline
runSequentially();
