import { onBeforeUnmount, ref, watch } from 'vue';
import API from 'dashboard/api/jrcContactCenter';

// No storage locator, token in the URL or cached cross-conversation media; exact bytes and receipt are checked again.
export const useAudioBytes = ({
  accountId,
  assetId,
  version,
  inspectionId,
  canManage,
  onDenied,
}) => {
  const url = ref('');
  const loading = ref(false);
  const error = ref('');
  let generation = 0;
  const clear = () => {
    generation += 1;
    const previous = url.value;
    url.value = '';
    if (previous) URL.revokeObjectURL(previous);
    loading.value = false;
    error.value = '';
  };
  const validIdentity = response => {
    const headers = response.headers;
    const current = version.value;
    return (
      headers['x-jrc-audio-account'] === String(accountId.value) &&
      headers['x-jrc-audio-unit'] === current.unit_id &&
      headers['x-jrc-audio-version'] === current.id &&
      headers['x-jrc-audio-inspection'] === inspectionId.value &&
      headers['x-jrc-audio-sha256'] === current.sha256 &&
      response.data instanceof Blob &&
      response.data.size === current.byte_size &&
      response.data.type.split(';', 1)[0].trim() === current.content_type
    );
  };
  const open = async () => {
    if (!canManage.value || !inspectionId.value || loading.value) return;
    clear();
    const current = generation;
    loading.value = true;
    try {
      const response = await API.audioBytes(
        accountId.value,
        assetId.value,
        version.value.id
      );
      if (current !== generation) return;
      if (!validIdentity(response))
        throw new Error('Invalid exact audio byte identity');
      const buffer = await response.data.arrayBuffer();
      const digest = await crypto.subtle.digest('SHA-256', buffer);
      if (current !== generation) return;
      const hash = Array.from(new Uint8Array(digest), value =>
        value.toString(16).padStart(2, '0')
      ).join('');
      if (hash !== version.value.sha256)
        throw new Error('Invalid exact audio byte digest');
      url.value = URL.createObjectURL(response.data);
    } catch (problem) {
      if (current !== generation) return;
      if ([401, 403, 404].includes(problem?.response?.status)) {
        clear();
        onDenied();
      } else
        error.value = problem?.response?.status === 409 ? 'NOT_READY' : 'ERROR';
    } finally {
      if (current === generation) loading.value = false;
    }
  };
  const playbackFailed = () => {
    error.value = 'PLAYBACK_ERROR';
  };
  const download = async () => {
    if (!canManage.value || !inspectionId.value || loading.value) return;
    const expected = generation + 1;
    await open();
    if (generation !== expected || !url.value) return;
    const link = document.createElement('a');
    link.href = url.value;
    link.download = version.value.file_name;
    link.click();
  };
  watch([accountId, assetId, version, inspectionId, canManage], clear, {
    flush: 'sync',
  });
  onBeforeUnmount(clear);
  return { url, loading, error, open, clear, playbackFailed, download };
};
