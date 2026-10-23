import { computed, onBeforeUnmount, shallowRef, watch } from 'vue';

// Presentation ownership only. The SIP client and audio remain global.
const host = shallowRef(null);
export const hasEmbeddedSoftphone = accountId =>
  host.value?.accountId === Number(accountId);
export const embeddedSoftphoneAccount = computed(() => host.value?.accountId);
export const openEmbeddedSoftphone = (accountId, number) => {
  if (!hasEmbeddedSoftphone(accountId)) return false;
  host.value.open(number);
  return true;
};
export function useEmbeddedSoftphone(accountId, enabled, open) {
  const owner = Symbol('embedded-softphone');
  const release = () => {
    if (host.value?.owner === owner) host.value = null;
  };
  watch(
    [accountId, enabled],
    ([id, allowed]) => {
      release();
      if (allowed) host.value = { owner, accountId: Number(id), open };
    },
    { immediate: true }
  );
  onBeforeUnmount(release);
}
