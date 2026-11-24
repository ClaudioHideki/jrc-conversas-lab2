import { test as base, expect } from '@playwright/test';
import fs from 'node:fs';
import { createHash } from 'node:crypto';

export { expect };

// Several native scenarios open a child page. Playwright's default failure
// screenshot belongs to the parent, which may be about:blank. Preserve the real
// synthetic child UI without catching, skipping or replacing any test failure.
export const test = base.extend({
  nativeChildEvidence: [
    async ({ context }, use, info) => {
      await use();
      if (info.status === info.expectedStatus) return;
      const images = [];
      for (const [index, page] of context.pages().entries()) {
        if (page.isClosed()) continue;
        const url = new URL(page.url());
        if (!['http://127.0.0.1:5386', 'http://127.0.0.1:5387'].includes(url.origin))
          continue;
        const path = info.outputPath(`native-child-${index}.png`);
        try {
          await page.screenshot({ path, timeout: 5000 });
          images.push({
            path,
            sha256: createHash('sha256').update(fs.readFileSync(path)).digest('hex'),
            location: url.origin + url.pathname,
          });
        } catch {
          images.push({ location: url.origin + url.pathname, screenshot_unavailable: true });
        }
      }
      await info.attach('native-child-page-diagnostics', {
        body: Buffer.from(JSON.stringify({
          sha: process.env.GITHUB_SHA,
          project: info.project.name,
          actual_status: info.status,
          expected_status: info.expectedStatus,
          diagnostic_only_not_acceptance: true,
          images,
        })),
        contentType: 'application/json',
      });
    },
    { auto: true },
  ],
});
