import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';

const require = createRequire(
  new URL('../../../../../package.json', import.meta.url)
);
const postcssRequire = createRequire(require.resolve('postcss'));
const { SourceMapConsumer } = postcssRequire('source-map-js');
const observations = new WeakMap();
const ownedOrigins = new Set([
  'http://127.0.0.1:5386',
  'http://127.0.0.1:5387',
]);
const scrub = value =>
  String(value || '')
    .replace(
      /((?:access[-_]token|authorization|password|secret)\s*[:=]\s*)[^\s,;]+/gi,
      '$1[REDACTED]'
    )
    .slice(0, 1500);

// Failure-only diagnostics: never record headers, queries, request/response bodies or source-map contents.
export function observeNativeChild(page) {
  const rows = { errors: [], api: [] };
  observations.set(page, rows);
  page.on('pageerror', error => {
    if (rows.errors.length < 20)
      rows.errors.push({
        name: scrub(error.name),
        message: scrub(error.message),
        stack: scrub(error.stack),
      });
  });
  page.on('response', response => {
    const url = new URL(response.url());
    if (
      ownedOrigins.has(url.origin) &&
      url.pathname.startsWith('/api/') &&
      rows.api.length < 120
    )
      rows.api.push({
        path: url.pathname,
        method: response.request().method(),
        status: response.status(),
      });
  });
}

function originalFrames(stack) {
  const directory = path.resolve('.codex/call-center-native-static');
  const matches = Array.from(
    stack.matchAll(/(http:\/\/127\.0\.0\.1:538[67]\/[^)\s]+):(\d+):(\d+)/g)
  );
  return matches.slice(0, 12).flatMap(match => {
    const url = new URL(match[1]);
    const file = path.resolve(directory, `.${url.pathname}`);
    if (!file.startsWith(directory + path.sep) || !file.endsWith('.js'))
      return [];
    const frame = {
      asset: url.pathname,
      line: Number(match[2]),
      column: Number(match[3]),
    };
    try {
      const consumer = new SourceMapConsumer(
        JSON.parse(fs.readFileSync(file + '.map', 'utf8'))
      );
      const original = consumer.originalPositionFor({
        line: frame.line,
        column: frame.column - 1,
      });
      frame.original = {
        source: original.source,
        line: original.line,
        column: original.column,
        name: original.name,
      };
    } catch {
      frame.mapping_unavailable = true;
    }
    return [frame];
  });
}

export async function preserveNativeChildFailure(info, family, pages) {
  if (!/^[a-z-]+$/.test(family)) throw new Error('Invalid diagnostic family');
  const children = await Promise.all(
    pages.map(async (page, index) => {
      const rows = observations.get(page) || { errors: [], api: [] };
      const screenshot = `.codex/call-center-native-e2e/${info.project.name}-${family}-failed-child-${index}.png`;
      if (!page.isClosed())
        await page.screenshot({
          path: screenshot,
          fullPage: true,
          timeout: 5000,
        });
      return {
        index,
        screenshot,
        api: rows.api,
        errors: rows.errors.map(error => ({
          ...error,
          frames: originalFrames(error.stack),
        })),
      };
    })
  );
  fs.writeFileSync(
    `.codex/call-center-native-e2e/${info.project.name}-${family}-failure-diagnostic.json`,
    JSON.stringify(
      {
        sha: process.env.GITHUB_SHA,
        project: info.project.name,
        synthetic: true,
        accepted: false,
        captured_before_child_cleanup: true,
        children,
      },
      null,
      2
    ) + '\n'
  );
}
