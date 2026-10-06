const memory = new Map();
const forbidden = /token|password|credential|secret|authorization|authentication|signature|attachment|file|binary/i;
const identifier = value => /^[1-9]\d*$/.test(String(value || ''));

export function draftKey(accountId, userId, formType) {
  if (!identifier(accountId) || !identifier(userId) || !/^[a-z0-9_:.-]+$/i.test(formType)) return null;
  return 'jrc:draft:account:' + accountId + ':user:' + userId + ':' + formType;
}

export function safeDraft(value) {
  if (value === null || ['string', 'boolean'].includes(typeof value)) return value;
  if (typeof value === 'number') return Number.isFinite(value) ? value : null;
  if (Array.isArray(value)) return value.map(safeDraft).filter(item => item !== undefined);
  if (!value || Object.getPrototypeOf(value) !== Object.prototype) return undefined;
  return Object.fromEntries(
    Object.entries(value)
      .filter(([key]) => !forbidden.test(key) && !['__proto__', 'constructor', 'prototype'].includes(key))
      .map(([key, item]) => [key, safeDraft(item)])
      .filter(([, item]) => item !== undefined)
  );
}

const browserStorage = () => {
  try { return globalThis.sessionStorage; } catch { return null; }
};

export function readDraft(key, storage = browserStorage()) {
  if (!key) return null;
  let serialized;
  try { serialized = storage ? storage.getItem(key) : memory.get(key); } catch { serialized = memory.get(key); }
  if (!serialized) return null;
  try {
    const record = JSON.parse(serialized);
    return record.version === 1 ? safeDraft(record.data) : null;
  } catch { return null; }
}

export function saveDraft(key, data, storage = browserStorage()) {
  if (!key) return;
  const serialized = JSON.stringify({ version: 1, data: safeDraft(data) });
  memory.set(key, serialized);
  try { storage?.setItem(key, serialized); } catch { /* Preserve the in-memory draft when storage is unavailable. */ }
}

export function clearDraft(key, storage = browserStorage()) {
  if (!key) return;
  memory.delete(key);
  try { storage?.removeItem(key); } catch { /* The in-memory copy is already discarded. */ }
}
