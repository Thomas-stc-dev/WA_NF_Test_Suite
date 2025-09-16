const puppeteer = require('puppeteer');

const pageUrl = 'https://40ab-61-82-105-69.ngrok-free.app/test'; // Replace with your page URL
const refreshInterval = 5000; // Refresh every 1 second (1000ms)

async function autoRefreshPage() {
    const browser = await puppeteer.launch({
        headless: false, // Keep browser visible to see the refreshing
        args: [
            '--disable-extensions',
            '--no-sandbox',
            '--disable-setuid-sandbox',
            '--disable-web-security',
            '--disable-features=IsolateOrigins,site-per-process',
            '--disable-same-origin-policy',
            '--allow-running-insecure-content',
            '--disable-features=VizDisplayCompositor',
            '--ignore-certificate-errors',
            '--ignore-ssl-errors',
            '--ignore-certificate-errors-spki-list'
        ],
    });

    const page = await browser.newPage();



    // Additional page-level settings
    await page.setBypassCSP(true);

    console.log(`Opening page: ${pageUrl}`);
    await page.goto(pageUrl);

    const ngrokButton = '#root > div > main > div > div > section.mb-4.border.border-gray-300.bg-white.shadow-md > div > footer > button';

    try {
        await page.waitForSelector(ngrokButton, { timeout: 10000 });
        await page.click(ngrokButton);

    } catch (error) {
        console.error(`Failed to click ngrok button`, error);
    }

    let refreshCount = 0;

    // Continuously refresh the page every 1 second
    const refresher = setInterval(async () => {
        try {
            refreshCount++;
            console.log(`Refresh #${refreshCount} at ${new Date().toLocaleTimeString()}`);
            await page.reload({ waitUntil: 'networkidle0' });
        } catch (error) {
            console.error(`Error during refresh #${refreshCount}:`, error);
        }
    }, refreshInterval);

    // Handle graceful shutdown (Ctrl+C)
    process.on('SIGINT', async () => {
        console.log('\nStopping auto-refresh...');
        clearInterval(refresher);
        await browser.close();
        process.exit(0);
    });

    // Keep the script running
    console.log(`Auto-refresh started. Page will refresh every ${refreshInterval}ms`);
    console.log('Press Ctrl+C to stop');
}

// Start the auto-refresh
autoRefreshPage().catch(console.error);