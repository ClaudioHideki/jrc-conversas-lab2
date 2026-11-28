// Extends the existing real native capture case before its original upload
// flow. Opening this editor does not request a microphone or persist a file.
export async function reviewDirectAudioCaptureEntry(page, expect) {
  await page
    .locator('[data-audio-asset-library] [data-new-audio-capture]')
    .click();
  const dialog = page.getByRole('dialog');
  const capture = dialog.locator('[data-institutional-capture]');
  await expect(capture).toBeVisible();
  await expect(dialog.locator('[data-audio-asset-file]')).toHaveCount(0);
  await expect(
    capture.locator('[data-start-institutional-capture]')
  ).toBeEnabled();
  await expect(
    capture.locator('[data-stop-institutional-capture]')
  ).toHaveCount(0);
  await expect(
    dialog.getByRole('button', { name: 'Salvar', exact: true })
  ).toBeDisabled();
  await dialog.getByRole('button', { name: 'Cancelar', exact: true }).click();
  await expect(dialog).toHaveCount(0);
}
