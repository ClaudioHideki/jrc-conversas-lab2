// Reuse the real native folder editor. No write, fixture mutation or provider I/O.
export async function reviewFolderOrganizationEntry(page, expect, target) {
  const origin = page.url();
  const library = page.locator('[data-audio-folder-library]');
  const shortcut = library.locator('[data-organize-audio-folders]');
  await expect(shortcut).toHaveText('Organizar Pastas');
  await expect(shortcut).toBeDisabled();
  await library
    .locator(`[data-open-audio-folder="${target.audio_folder_id}"]`)
    .click();
  await expect(shortcut).toBeEnabled();
  let writes = 0;
  const observe = request => {
    if (
      new URL(request.url()).pathname.startsWith(
        `/api/v1/accounts/${target.account_id}/jrc_contact_center/audio_folders`
      ) &&
      !['GET', 'HEAD'].includes(request.method())
    )
      writes += 1;
  };
  page.on('request', observe);
  try {
    await shortcut.click();
    const dialog = page.getByRole('dialog');
    await expect(dialog).toBeVisible();
    await expect(dialog.locator('[data-audio-folder-name]')).toHaveValue(
      target.audio_folder_name
    );
    await expect(
      dialog.getByRole('button', { name: 'Salvar pasta', exact: true })
    ).toBeDisabled();
    await expect(dialog.locator('[data-audio-folder-parent]')).toBeVisible();
    await dialog.getByRole('button', { name: 'Cancelar', exact: true }).click();
    await expect(dialog).not.toBeVisible();
    expect(writes).toBe(0);
  } finally {
    page.off('request', observe);
  }
  await page.goto(origin);
  await expect(library.locator('[data-audio-folder]')).toHaveCount(1);
}
