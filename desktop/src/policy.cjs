const APP_ID = 'br.com.jrcpabx.softphone';
const parseUrl = value => {
  try {
    return new URL(value);
  } catch {
    return null;
  }
};

function serverOrigin(value) {
  if (typeof value !== 'string' || value.length > 2048)
    throw new Error('Informe um endereço HTTPS válido, sem usuário ou senha.');
  const input = value.trim();
  const authority = /^https:\/\/([^/?#]+)/i.exec(input)?.[1];
  const url = parseUrl(input);
  if (
    !authority ||
    authority.includes('@') ||
    /[\s\\]/u.test(input) ||
    !url ||
    url.protocol !== 'https:' ||
    url.username ||
    url.password ||
    !url.hostname ||
    (!url.hostname.startsWith('[') &&
      !url.hostname
        .replace(/\.$/, '')
        .split('.')
        .every(label => /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/i.test(label)))
  )
    throw new Error('Informe um endereço HTTPS válido, sem usuário ou senha.');
  return url.origin;
}

function serverConfig({ argv, env, isPackaged, savedOrigin }) {
  const argument = argv.find(value => value.startsWith('--server-url='));
  const development = !isPackaged && argv.includes('--development');
  const value =
    (!development && savedOrigin) ||
    env.JRC_SOFTPHONE_URL ||
    argument?.slice('--server-url='.length) ||
    savedOrigin;
  if (!value) return null;
  const url = parseUrl(value);
  const localDevelopment =
    development && ['localhost', '127.0.0.1', '[::1]'].includes(url?.hostname);
  if (
    !url ||
    url.username ||
    url.password ||
    (url.protocol !== 'https:' &&
      !(url.protocol === 'http:' && localDevelopment))
  ) {
    throw new Error(
      'Configure a URL HTTPS do JRC. HTTP é permitido somente no desenvolvimento local explícito.'
    );
  }
  if (localDevelopment && url.protocol === 'http:')
    return { url: url.href, origin: url.origin, localDevelopment: true };
  const origin = serverOrigin(value);
  return { url: origin, origin, localDevelopment: false };
}

function trustedUrl(value, origin) {
  const url = parseUrl(value);
  return Boolean(
    url &&
      ['https:', 'http:'].includes(url.protocol) &&
      url.origin === origin &&
      !url.username &&
      !url.password
  );
}

function trustedSender(event, window, origin) {
  return Boolean(
    window &&
      !window.isDestroyed() &&
      event.sender === window.webContents &&
      event.senderFrame &&
      event.senderFrame === window.webContents.mainFrame &&
      trustedUrl(event.senderFrame.url, origin)
  );
}

function audioPermission(
  webContents,
  window,
  origin,
  permission,
  details = {},
  requestingOrigin = undefined
) {
  if (
    !window ||
    window.isDestroyed() ||
    webContents !== window.webContents ||
    permission !== 'media' ||
    details.isMainFrame !== true ||
    !trustedUrl(webContents.getURL(), origin) ||
    !trustedUrl(details.requestingUrl, origin) ||
    (requestingOrigin && !trustedUrl(requestingOrigin, origin))
  )
    return false;
  if (Array.isArray(details.mediaTypes)) {
    return details.mediaTypes.length === 1 && details.mediaTypes[0] === 'audio';
  }
  return details.mediaType === 'audio';
}

const boundedText = (value, max) =>
  typeof value === 'string' &&
  value.length > 0 &&
  value.length <= max &&
  // Reject control characters and bidi controls in untrusted notification text.
  // eslint-disable-next-line no-control-regex
  !/[\u0000-\u001f\u007f\u202a-\u202e\u2066-\u2069]/u.test(value);
const recordWithKeys = (value, keys) =>
  value !== null &&
  typeof value === 'object' &&
  !Array.isArray(value) &&
  Object.keys(value).length === keys.length &&
  keys.every(key => Object.hasOwn(value, key));

function incomingPayload(payload) {
  return (
    recordWithKeys(payload, ['callId', 'remote']) &&
    boundedText(payload.callId, 256) &&
    boundedText(payload.remote, 128)
  );
}
function clearPayload(payload) {
  return (
    recordWithKeys(payload, ['callId']) && boundedText(payload.callId, 256)
  );
}
const floatingStateKeys = [
  'registered',
  'status',
  'extension',
  'destination',
  'remote',
  'duration',
  'incoming',
  'sessionActive',
  'established',
  'muted',
  'held',
  'holdPending',
  'transferring',
  'errorMessage',
];
function floatingState(payload) {
  return (
    recordWithKeys(payload, floatingStateKeys) &&
    [
      'registered',
      'incoming',
      'sessionActive',
      'established',
      'muted',
      'held',
      'holdPending',
      'transferring',
    ].every(key => typeof payload[key] === 'boolean') &&
    [
      'status',
      'extension',
      'destination',
      'remote',
      'duration',
      'errorMessage',
    ].every(key => boundedText(payload[key] || '—', 256))
  );
}
function floatingCommand(payload) {
  if (!payload || typeof payload !== 'object' || Array.isArray(payload))
    return false;
  if (
    [
      'answer',
      'reject',
      'hangup',
      'toggleMute',
      'toggleHold',
      'showMain',
    ].includes(payload.action)
  )
    return Object.keys(payload).length === 1;
  if (payload.action === 'dtmf')
    return (
      recordWithKeys(payload, ['action', 'tone']) &&
      /^[0-9*#]$/.test(payload.tone)
    );
  if (payload.action === 'dial')
    return (
      recordWithKeys(payload, ['action', 'number']) &&
      /^[0-9*#+()\-\s]{1,128}$/.test(payload.number)
    );
  if (payload.action === 'setDestination')
    return (
      recordWithKeys(payload, ['action', 'number']) &&
      typeof payload.number === 'string' &&
      /^[0-9*#+()\-\s]{0,128}$/.test(payload.number)
    );
  return (
    payload.action === 'transfer' &&
    recordWithKeys(payload, ['action', 'mode', 'destination']) &&
    ['immediate', 'supervised'].includes(payload.mode) &&
    /^[0-9+()\-\s]{1,128}$/.test(payload.destination)
  );
}
function contactUrl(payload, origin) {
  if (
    !recordWithKeys(payload, ['accountId', 'contactId']) ||
    ![payload.accountId, payload.contactId].every(
      value => typeof value === 'string' && /^[1-9]\d{0,15}$/.test(value)
    )
  )
    return null;
  return `${origin}/app/accounts/${payload.accountId}/contacts/${payload.contactId}`;
}
function externalUrl(value, origin) {
  const url = parseUrl(value);
  if (
    !trustedUrl(value, origin) ||
    url.search ||
    url.hash ||
    !/^\/app(?:\/accounts\/[1-9]\d{0,15}(?:\/contacts\/[1-9]\d{0,15}|\/ramal)?)?\/?$/.test(
      url.pathname
    )
  )
    return null;
  return url.href;
}

// Bound native notifications and remember closed call IDs, not only the active toast.
function notificationGate(now = Date.now) {
  const calls = new Map();
  let recent = [];
  return callId => {
    const time = now();
    calls.forEach((timestamp, id) => {
      if (time - timestamp >= 600000) calls.delete(id);
    });
    recent = recent.filter(timestamp => time - timestamp < 10000);
    if (calls.has(callId) || recent.length >= 5) return false;
    if (calls.size >= 256) calls.delete(calls.keys().next().value);
    calls.set(callId, time);
    recent.push(time);
    return true;
  };
}
module.exports = {
  APP_ID,
  serverOrigin,
  serverConfig,
  trustedUrl,
  trustedSender,
  audioPermission,
  incomingPayload,
  clearPayload,
  floatingState,
  floatingCommand,
  contactUrl,
  externalUrl,
  notificationGate,
};
