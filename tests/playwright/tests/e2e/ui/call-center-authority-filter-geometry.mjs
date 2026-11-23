import { expect } from '@playwright/test';

export async function verifyAuthorityFilterGeometry(page, project) {
  const form = page.locator('[data-authority-filters]');
  await expect(form).toBeVisible();
  await form.scrollIntoViewIfNeeded();
  const geometry = await form.evaluate(node => {
    const labels = [...node.querySelectorAll('label')].map(label => {
      const box = label.getBoundingClientRect();
      const control = label
        .querySelector('input, select')
        .getBoundingClientRect();
      return {
        top: box.top,
        bottom: box.bottom,
        left: box.left,
        right: box.right,
        controlTop: control.top,
        controlBottom: control.bottom,
        controlLeft: control.left,
        controlRight: control.right,
        controlWidth: control.width,
      };
    });
    return {
      labels,
      width: window.innerWidth,
      noOverflow: document.documentElement.scrollWidth <= window.innerWidth,
    };
  });
  const visible = await form.boundingBox();
  expect(visible).not.toBeNull();
  expect(visible.y).toBeGreaterThanOrEqual(-1);
  expect(visible.y + visible.height).toBeLessThanOrEqual(
    page.viewportSize().height + 1
  );
  expect(geometry.labels).toHaveLength(2);
  expect(geometry.noOverflow).toBe(true);
  for (const label of geometry.labels) {
    expect(label.controlWidth).toBeGreaterThan(100);
    expect(label.controlLeft).toBeGreaterThanOrEqual(label.left - 1);
    expect(label.controlRight).toBeLessThanOrEqual(label.right + 1);
    expect(label.controlTop).toBeGreaterThan(label.top);
    expect(label.controlBottom).toBeLessThanOrEqual(label.bottom + 1);
  }
  if (geometry.width === 390)
    expect(geometry.labels[1].top).toBeGreaterThanOrEqual(
      geometry.labels[0].controlBottom + 8
    );
  await page.screenshot({
    path: `.codex/call-center-native-e2e/${project}-authority-filters-closed.png`,
  });
}
