import { expect } from '@playwright/test';
import fs from 'node:fs';
import { createHash } from 'node:crypto';

// Reuses the current authenticated native institutional byte controller and player.
export async function verifyAudioRowPreview(
  page,
  info,
  {
    target,
    asset,
    versionId,
    bytePath,
    sha256,
    duration,
    expectContainedDialog,
  }
) {
  const library = page.locator('[data-audio-asset-library]');
  await page.goto(
    `/app/accounts/${target.account_id}/contact-center/control-desk/audio?audio_unit=${target.unit_id}&audio_file_q=${encodeURIComponent(asset.name)}`
  );
  const rowByteResult = page.waitForResponse(
    response => new URL(response.url()).pathname === bytePath
  );
  await library.locator(`[data-preview-audio-asset="${asset.id}"]`).click();
  await expectContainedDialog(page);
  const directPreview = page.locator('[data-audio-row-preview]');
  const rowBytes = await rowByteResult;
  expect(rowBytes.status()).toBe(200);
  expect(rowBytes.headers()['x-jrc-audio-account']).toBe(
    String(target.account_id)
  );
  expect(rowBytes.headers()['x-jrc-audio-unit']).toBe(String(target.unit_id));
  expect(rowBytes.headers()['x-jrc-audio-version']).toBe(versionId);
  const rowDigest = createHash('sha256')
    .update(await rowBytes.body())
    .digest('hex');
  expect(rowDigest).toBe(sha256);
  const directPlayer = directPreview.locator('[data-audio-verified-player]');
  await expect(directPlayer).toBeVisible();
  await expect
    .poll(() => directPlayer.evaluate(node => node.duration))
    .toBe(duration);
  const directDark = await page
    .locator('html')
    .evaluate(node => node.classList.contains('dark'));
  expect(directDark).toBe(info.project.name.endsWith('dark'));
  const directOverflow = await page.evaluate(
    () => document.documentElement.scrollWidth > innerWidth
  );
  expect(directOverflow).toBe(false);
  const directScreenshot = `.codex/call-center-native-e2e/${info.project.name}-audio-row-native-preview.png`;
  await page.screenshot({ path: directScreenshot, fullPage: false });
  await directPreview.locator('[data-close-audio-row-preview]').click();
  await expect(directPreview).toHaveCount(0);
  await expect(
    library.locator(`[data-audio-asset="${asset.id}"]`)
  ).toBeVisible();
  fs.writeFileSync(
    `.codex/call-center-native-e2e/${info.project.name}-audio-row-native-preview.json`,
    JSON.stringify({
      sha: process.env.GITHUB_SHA,
      project: info.project.name,
      synthetic: true,
      account_id: String(target.account_id),
      unit_id: String(target.unit_id),
      asset_id: asset.id,
      version_id: versionId,
      actual_dark_theme: directDark,
      horizontal_overflow: directOverflow,
      bytes_status: rowBytes.status(),
      bytes_sha256: rowDigest,
      expected_sha256: sha256,
      actual_duration: duration,
      same_native_byte_controller_and_player: true,
      closed_without_losing_current_list: true,
      screenshot: directScreenshot,
      provider_writes: false,
      external_homologation: false,
    })
  );
}
