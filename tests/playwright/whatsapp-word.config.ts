import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './tests/e2e/ui',
  testMatch: 'whatsapp-word.spec.ts',
  workers: 1,
  retries: 0,
  timeout: 90000,
  expect: { timeout: 30000 },
  reporter: 'line',
  outputDir: '../../.codex/whatsapp-word-e2e',
  use: {
    baseURL: 'http://127.0.0.1:5214',
    headless: true,
    locale: 'pt-BR',
    timezoneId: 'America/Sao_Paulo',
  },
  webServer: {
    command:
      'pnpm exec vite --config tests/playwright/fixtures/whatsapp-word/vite.config.mjs',
    cwd: '../..',
    url: 'http://127.0.0.1:5214/tests/playwright/fixtures/whatsapp-word/index.html',
    reuseExistingServer: false,
    timeout: 180000,
  },
  projects: [
    { name: 'desktop', use: { viewport: { width: 1440, height: 1000 } } },
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
