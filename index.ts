const puppeteer = require("puppeteer");
const {
  getProxiesFromFreeProxyList,
  getProxyPool,
} = require("./get-proxy-ips");
const pageUrl = "http://nf-integration-testing.waveautoscale.io/"; // Replace with your page URL
// const pageUrl = "http://100.96.40.60:8080/test"; // Replace with your page URL

// const instances = 1; // Number of browser instances to run simultaneously
const delay = 1; // Delay in seconds between each iteration
const totalRequests = 1000; // Total number of requests to send

const proxies = [
  "13.112.112.228:8888",
  "52.198.174.19:8888",
  "35.77.85.221:8888",
  "18.183.119.218:8888",
  "35.78.185.172:8888",
  // "3.112.97.111:8888",
  // "18.179.62.213:8888",
  "", //direct
]

// Global stats tracking
const stats = {
  totalSuccess: 0,
  totalFailures: 0,
  instanceStats: new Map(),
  startTime: Date.now(),
  last10Sec: [] as { time: number; success: number }[],
};

// Initialize instance stats
for (let i = 1; i <= proxies.length; i++) {
  stats.instanceStats.set(i, {
    success: 0,
    failures: 0,
    status: "Starting...",
  });
}

// Update display every 2 seconds
setInterval(() => {
  console.clear();
  console.log("=".repeat(120));
  console.log("🚀 TRAFFIC GENERATOR DASHBOARD");
  console.log("=".repeat(120));

  const runtime = Math.floor((Date.now() - stats.startTime) / 1000);
  const totalRequests = stats.totalSuccess + stats.totalFailures;
  const successRate =
    totalRequests > 0
      ? ((stats.totalSuccess / totalRequests) * 100).toFixed(1)
      : "0.0";

  console.log(
    `Runtime: ${runtime}s | Total Requests: ${totalRequests} | Success Rate: ${successRate}%`
  );
  console.log(
    `Total Success: ${stats.totalSuccess} | Total Failures: ${stats.totalFailures}`
  );
  const rps = runtime > 0 ? (stats.totalSuccess / runtime).toFixed(2) : "0.00";
  console.log(`Success per Second (SPS): ${rps}`);
  // Calculate requests served in the last 10 seconds
  const now = Date.now();
  if (!stats.last10Sec) stats.last10Sec = [];
  stats.last10Sec.push({ time: now, success: stats.totalSuccess });

  // Remove entries older than 10 seconds
  stats.last10Sec = stats.last10Sec.filter(
    (entry) => now - entry.time <= 10000
  );

  const oldest = stats.last10Sec[0]?.success ?? 0;
  const servedLast10Sec = stats.totalSuccess - oldest;
  console.log(`Requests served in last 10 seconds in SPS: ${servedLast10Sec / 10}/s`);
  console.log("-".repeat(120));

  // Show per-instance stats
  stats.instanceStats.forEach((stat, instanceId) => {
    const total = stat.success + stat.failures;
    const rate = total > 0 ? ((stat.success / total) * 100).toFixed(1) : "0.0";
    console.log(
      `Instance ${instanceId < 10 ? `0${instanceId}` : instanceId}: ${
        stat.status
      } | Requests: ${total} | Success: ${stat.success} (${rate}%) | Failure: ${
        stat.failures
      } (${
        total > 0 ? ((stat.failures / total) * 100).toFixed(1) : "0.0"
      }%) | proxy: ${proxies[instanceId - 1] || "DIRECT CONNECTION"}`
    );
  });

  console.log("=".repeat(120));
}, 2000);

async function clickButtons(instanceId: number, proxy: string) {
  console.log(
    `🌐 Instance ${instanceId} using proxy: ${proxy || "DIRECT CONNECTION"}`
  );

  const browserArgs = [
    "--disable-extensions",
    "--no-sandbox",
    "--disable-setuid-sandbox",
    "--disable-web-security",
    "--disable-features=IsolateOrigins,site-per-process",
    "--disable-same-origin-policy",
    "--allow-running-insecure-content",
    "--disable-features=VizDisplayCompositor",
    "--ignore-certificate-errors",
    "--ignore-ssl-errors",
    "--ignore-certificate-errors-spki-list",
    "--disable-gpu-sandbox",
    "--disable-webgl",
    "--disable-client-side-phishing-detection",
    "--disable-sync",
    "--disable-background-networking",
    "--disable-background-timer-throttling",
    "--disable-backgrounding-occluded-windows",
    "--disable-renderer-backgrounding",
    "--disable-features=TranslateUI",
    "--disable-ipc-flooding-protection",
    "--disable-hang-monitor",
    "--disable-prompt-on-repost",
    "--disable-domain-reliability",
    "--no-first-run",
    "--disable-default-apps",
    "--disable-component-extensions-with-background-pages",
    "--disable-site-isolation-trials",
    "--disable-features=VizDisplayCompositor,VizHitTestSurfaceLayer",
    "--disable-blink-features=AutomationControlled",
    "--disable-dev-shm-usage",
    "--disable-accelerated-2d-canvas",
    "--disable-background-timer-throttling",
    "--disable-backgrounding-occluded-windows",
    "--disable-renderer-backgrounding",
    "--disable-field-trial-config",
    "--disable-features=AudioServiceOutOfProcess",
    "--disable-features=BackgroundFetch",
    "--disable-features=Bluetooth",
    "--disable-features=ScriptStreaming",
    "--allow-insecure-localhost",
    "--ignore-ssl-errors-spki-list",
    "--ignore-certificate-errors-spki-list",
    "--enable-features=NetworkService,NetworkServiceLogging",
    "--disable-web-security",
    "--allow-running-insecure-content",
  ];

  // Add proxy if provided
  if (proxy) {
    browserArgs.unshift(`--proxy-server=http://${proxy}`);
    browserArgs.push("--proxy-bypass-list=<-loopback>");
  }

  const browser = await puppeteer.launch({
    headless: false, // Try headless mode
    args: browserArgs,
  });
  const page = await browser.newPage();

  // Enable request interception to bypass blocking
  await page.setRequestInterception(true);
  page.on("request", (request: any) => {
    // Allow all requests to proceed
    request.continue();
  });

  // Additional page-level settings to allow mixed content
  await page.setBypassCSP(true);

  // Set a user agent to avoid bot detection
  await page.setUserAgent(
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"
  );
  // Update instance status
  stats.instanceStats.get(instanceId).status = "Navigating...";

  try {
    await page.goto(pageUrl, { timeout: 120000 });
  } catch (navError: any) {
    console.error(
      `❌ Instance ${instanceId}: Navigation failed:`,
      navError?.message || navError
    );
    stats.instanceStats.get(instanceId).status = "Navigation Failed";
    await browser.close();
    return;
  }

  const button1 = "#button1";
  const button2 = "#button2";

  // Update instance status
  stats.instanceStats.get(instanceId).status = "Running";

  let successCount = 0;
  let failureCount = 0;

  for (let i = 0; i < totalRequests; i++) {
    // Refresh page, so when segment is blocked by NF reload will cause the queue message to show up
    await page.reload({ waitUntil: ["networkidle0", "domcontentloaded"] });
    try {
      await page.waitForSelector(button1, { timeout: 1000 });
      // click 5 times quickly to simulate multiple requests
      for (let j = 0; j < 10; j++) {
        await page.click(button1);
        await new Promise((resolve) => setTimeout(resolve, 10)); // 0.01 second delay between clicks
      }
      await page.click(button1);

      // await page.waitForSelector(button2, { timeout: 1000 });
      // await page.click(button2);

      // Update stats
      successCount++;
      stats.totalSuccess++;
      stats.instanceStats.get(instanceId).success = successCount;
    } catch (error) {
      // Update failure stats
      failureCount++;
      stats.totalFailures++;
      stats.instanceStats.get(instanceId).failures = failureCount;
      continue; // If an error occurs, continue to the next iteration
    }

    // Wait 0.1 seconds before next iteration
    await new Promise((resolve) => setTimeout(resolve, delay * 1000));
  }

  // Mark instance as completed
  stats.instanceStats.get(instanceId).status = "Completed";
  await browser.close();
}

(async () => {
  console.log(`🚀 Starting ${proxies.length} concurrent instances...`);
  const promises = [];
  // const proxyPool = await getProxyPool(5);
  for (let i = 1; i <= proxies.length; i++) {
    // Test with proxy now that we fixed the Chrome flags
    const proxy = proxies[i - 1];
    let workingProxy = proxy;
    try {
      const testBrowser = await puppeteer.launch({
        headless: true,
        args: [
          `--proxy-server=http://${proxy}`,
          "--no-sandbox",
          "--disable-setuid-sandbox",
        ],
      });
      const testPage = await testBrowser.newPage();
      await testPage.goto("https://www.google.com", { timeout: 10000 });
      await testBrowser.close();
    } catch {
      workingProxy = "";
    }
    promises.push(clickButtons(i, workingProxy ?? ""));
  }
  await Promise.all(promises);
  // console.clear();
  console.log("🎉 All instances completed!");
  console.log(
    `Final Stats - Success: ${stats.totalSuccess}, Failures: ${stats.totalFailures}`
  );
  process.exit(0);
})();
