import { ref } from 'vue';

// This proof exists only in this widget's memory. It is never added to Vuex,
// cookies, local/session storage, or the shared native Axios headers.
let attempt = 0;
let proof;
const revision = ref(0);

export const beginPortalIdentity = () => {
  attempt += 1;
  proof = undefined;
  revision.value += 1;
  return attempt;
};

export const capturePortalIdentity = (turn, identifier, token, authToken) => {
  if (
    turn !== attempt ||
    typeof identifier !== 'string' ||
    !identifier.trim() ||
    typeof token !== 'string' ||
    !/^[a-f0-9]{64}$/.test(token) ||
    typeof authToken !== 'string' ||
    !authToken
  )
    return;
  proof = { identifier, token, authToken, identity: Symbol('portal-identity') };
  revision.value += 1;
};

export const portalIdentity = authToken =>
  revision.value && proof && proof.authToken === authToken
    ? proof.identity
    : null;

export const portalIdentityHeaders = authToken => {
  if (!portalIdentity(authToken))
    throw new TypeError('Verified customer identity required');
  return {
    'X-Service-Desk-Identifier': proof.identifier,
    'X-Service-Desk-Identity-Token': proof.token,
  };
};
