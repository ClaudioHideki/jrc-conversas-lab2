// Runs inside the actual browser; computed CSS, alpha composition and WCAG luminance.
export function measureTextContrast(root, selectors = []) {
  const context = document.createElement('canvas').getContext('2d');
  const pixel = color => {
    context.clearRect(0, 0, 1, 1);
    context.fillStyle = color;
    context.fillRect(0, 0, 1, 1);
    return [...context.getImageData(0, 0, 1, 1).data];
  };
  const luminance = channels =>
    channels
      .slice(0, 3)
      .map(value => {
        const channel = value / 255;
        return channel <= 0.04045
          ? channel / 12.92
          : ((channel + 0.055) / 1.055) ** 2.4;
      })
      .reduce(
        (sum, value, index) => sum + value * [0.2126, 0.7152, 0.0722][index],
        0
      );
  const over = (front, back) => {
    const alpha = front[3] / 255;
    return front
      .slice(0, 3)
      .map((value, index) =>
        Math.round(value * alpha + back[index] * (1 - alpha))
      )
      .concat(255);
  };
  const surfaces = [];
  for (let node = root; node; node = node.parentElement) surfaces.unshift(node);
  const background = surfaces.reduce(
    (color, node) => over(pixel(getComputedStyle(node).backgroundColor), color),
    [255, 255, 255, 255]
  );
  const nodes = selectors.length
    ? selectors.flatMap(selector => [...root.querySelectorAll(selector)])
    : [root];
  return nodes.map(node => {
    const sourceForeground = pixel(getComputedStyle(node).color);
    const foreground = over(sourceForeground, background);
    const first = luminance(foreground);
    const second = luminance(background);
    return {
      foreground,
      background,
      sourceForeground,
      ratio:
        (Math.max(first, second) + 0.05) / (Math.min(first, second) + 0.05),
    };
  });
}
