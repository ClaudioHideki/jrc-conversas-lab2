import { defineConfig } from '@playwright/test';
export default defineConfig({
  testDir: './tests/e2e/ui',
  testMatch: 'call-center-native.spec.ts',
  workers: 1,
  retries: 0,
  timeout: 90000,
  reporter: [
    ['line'],
    ['json', { outputFile: '.codex/call-center-native-e2e/results.json' }],
  ],
  outputDir: '.codex/call-center-native-e2e/screenshots',
  use: {
    baseURL: 'http://127.0.0.1:5386',
    channel: 'chrome',
    headless: true,
    locale: 'pt-BR',
    timezoneId: 'America/Sao_Paulo',
    screenshot: 'only-on-failure',
  },
  projects: [
    {
      name: 'desktop-light',
      use: { viewport: { width: 1440, height: 1000 }, colorScheme: 'light' },
    },
    {
      name: 'desktop-dark',
      use: { viewport: { width: 1440, height: 1000 }, colorScheme: 'dark' },
    },
    {
      name: 'mobile-light',
      use: {
        viewport: { width: 390, height: 844 },
        isMobile: true,
        hasTouch: true,
        colorScheme: 'light',
      },
    },
    {
      name: 'mobile-dark',
      use: {
        viewport: { width: 390, height: 844 },
        isMobile: true,
        hasTouch: true,
        colorScheme: 'dark',
      },
    },
  ],
});
