// Only viewport positions are retained. Rows and permissions are always reloaded.
const positions = new Map();
export const rememberViewport = (key, position) => {
  if (!key) return;
  positions.delete(key);
  positions.set(key, position);
  if (positions.size > 50) positions.delete(positions.keys().next().value);
};
export const viewportPosition = key => positions.get(key) || 0;
