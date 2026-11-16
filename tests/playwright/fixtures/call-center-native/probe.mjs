import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';

const require = createRequire(new URL('../../package.json', import.meta.url));
const { chromium } = require('@playwright/test');
const repositoryRequire = createRequire(new URL('../../../../package.json', import.meta.url));
const postcssRequire = createRequire(repositoryRequire.resolve('postcss'));
const { SourceMapConsumer } = postcssRequire('source-map-js');
const session = JSON.parse(
  fs.readFileSync('/tmp/call-center-e2e-session.private', 'utf8')
);
const directory = path.resolve('.codex/call-center-native-e2e');
const report = { passed: false, pageErrors: [], pageErrorDetails: [], failedRequests: [], httpErrors: [] };

const assetsDirectory = path.resolve('.codex/call-center-native-static');
const sourceMaps = new Map();
const mapStack = stack => {
  const frames = [];
  for (const match of String(stack || '').matchAll(/(http:\/\/127\.0\.0\.1:5386\/[^)\s]+):(\d+):(\d+)/g)) {
    const url = new URL(match[1]);
    const generated = { path: url.pathname, line: Number(match[2]), column: Number(match[3]) };
    const frame = { generated };
    try {
      const file = path.resolve(assetsDirectory, `.${url.pathname}`);
      if (!file.startsWith(`${assetsDirectory}${path.sep}`) || !file.endsWith('.js')) {
        throw new Error('Stack frame is outside the isolated JavaScript assets');
      }
      if (!sourceMaps.has(file)) {
        sourceMaps.set(file, new SourceMapConsumer(JSON.parse(fs.readFileSync(`${file}.map`, 'utf8'))));
      }
      const original = sourceMaps.get(file).originalPositionFor({
        line: generated.line,
        column: generated.column - 1,
        bias: SourceMapConsumer.GREATEST_LOWER_BOUND,
      });
      frame.original = original;
      if (original.source) {
        frame.repositoryPath = path.relative(process.cwd(), path.resolve(path.dirname(file), original.source));
      }
    } catch (error) {
      frame.mappingError = error.message;
    }
    frames.push(frame);
  }
  return frames;
};

const browser = await chromium.launch({ channel: 'chrome', headless: true });
try {
  const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
  page.on('pageerror', error => {
    report.pageErrors.push(error.message);
    report.pageErrorDetails.push({ name: error.name, message: error.message, stack: error.stack, frames: mapStack(error.stack) });
  });
  page.on('requestfailed', request =>
    report.failedRequests.push({
      path: new URL(request.url()).pathname,
      error: request.failure()?.errorText,
    })
  );
  page.on('response', response => {
    if (response.status() >= 400)
      report.httpErrors.push({
        path: new URL(response.url()).pathname,
        status: response.status(),
      });
  });
  await page.addInitScript(auth => {
    window.__SYNTHETIC_AUTH__ = auth;
  }, session.administrator);
  await page.goto(
    `http://127.0.0.1:5386/app/accounts/${session.account_id}/contact-center/control-desk`,
    { waitUntil: 'domcontentloaded', timeout: 20000 }
  );
  await page
    .getByRole('heading', { name: 'Configurações do Call Center', exact: true })
    .waitFor({ state: 'visible', timeout: 20000 });
  // The heading is rendered before the authorized asynchronous card response.
  await page.locator('[data-card]').nth(14).waitFor({ state: 'visible', timeout: 20000 });
  report.cards = await page.locator('[data-card]').count();
  report.passed =
    report.cards === 15 &&
    report.pageErrors.length === 0 &&
    report.failedRequests.length === 0 &&
    report.httpErrors.length === 0;
} catch (error) {
  report.error = error.message;
} finally {
  await browser.close();
  fs.mkdirSync(directory, { recursive: true });
  fs.writeFileSync(
    path.join(directory, 'bootstrap.json'),
    `${JSON.stringify(report, null, 2)}\n`
  );
}
console.log(JSON.stringify(report));
if (!report.passed) process.exitCode = 1;
