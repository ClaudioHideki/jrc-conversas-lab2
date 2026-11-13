const { defineConfig } = require(process.env.JRC_PLAYWRIGHT_MODULE);
module.exports = defineConfig({
  testDir: __dirname,
  testMatch: 'approval_browser.spec.cjs',
  timeout: 120000,
  expect: { timeout: 20000 },
  workers: 1,
  maxFailures: 1,
  retries: 0,
  forbidOnly: true,
  reporter: [['list'], ['json', { outputFile: `${process.env.JRC_BROWSER_OUTPUT}/playwright-results.json` }]],
  outputDir: `${process.env.JRC_BROWSER_OUTPUT}/browser-results`,
  use: { headless: true, channel: 'chrome', screenshot: 'only-on-failure', trace: 'off' },
});
