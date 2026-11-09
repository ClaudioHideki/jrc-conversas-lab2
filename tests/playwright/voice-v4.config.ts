import { defineConfig } from '@playwright/test';
import path from 'node:path';
const evidenceDir = path.resolve(__dirname, '../../.codex/voice-v4-e2e');
export default defineConfig({
  testDir: './tests/e2e/ui',
  testMatch: 'voice-v4.spec.ts',
  workers: 1,
  retries: 0,
  timeout: 90000,
  expect: { timeout: 30000 },
  reporter: [['line'], ['json', { outputFile: `${evidenceDir}/results.json` }]],
  outputDir: evidenceDir,
  use: {
    baseURL: 'http://127.0.0.1:5226',
    headless: true,
    channel: process.env.JRC_VOICE_E2E_CHANNEL || undefined,
    locale: 'pt-BR',
    timezoneId: 'America/Sao_Paulo',
    screenshot: 'only-on-failure',
  },
  webServer: {
    command:
      'node node_modules/vite/bin/vite.js --config tests/playwright/fixtures/voice-v4/vite.config.mjs',
    cwd: '../..',
    url: 'http://127.0.0.1:5226/tests/playwright/fixtures/voice-v4/index.html',
    reuseExistingServer: !process.env.CI,
    timeout: 180000,
  },
  projects: [
    { name: 'tablet', use: { viewport: { width: 768, height: 1024 } } },
    {
      name: 'compact',
      use: {
        viewport: { width: 320, height: 800 },
        isMobile: true,
        hasTouch: true,
      },
    },
    { name: 'wide', use: { viewport: { width: 1920, height: 1080 } } },
    { name: 'desktop', use: { viewport: { width: 1440, height: 900 } } },
    { name: 'notebook', use: { viewport: { width: 1366, height: 768 } } },
    {
      name: 'mobile',
      use: {
        viewport: { width: 390, height: 844 },
        isMobile: true,
        hasTouch: true,
      },
    },
  ],
});
