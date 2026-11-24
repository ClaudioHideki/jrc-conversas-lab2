import { defineConfig } from '@playwright/test';
import path from 'node:path';

const evidence = path.resolve('.codex/call-center-native-e2e');
export default defineConfig({
  testDir: './tests/e2e/ui',
  testMatch: [
    'call-center-native.spec.ts',
    'call-center-ending-activation-native.spec.ts',
  ],
  workers: 1,
  retries: 0,
  timeout: 90000,
  reporter: [
    ['line'],
    ['json', { outputFile: path.join(evidence, 'results.json') }],
  ],
  outputDir: path.join(evidence, 'screenshots'),
  use: {
    baseURL: 'http://127.0.0.1:5386',
    channel: 'chrome',
    headless: true,
    // This synthetic local suite must never access a physical microphone.
    launchOptions: { args: ['--use-fake-device-for-media-stream'] },
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
