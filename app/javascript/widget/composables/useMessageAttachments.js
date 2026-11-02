import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { API, widgetIdentityRevision } from 'widget/helpers/axios';
import { getProtectedAttachment } from 'widget/api/messageAttachments';

// An ObjectURL does not inherit response CSP or Content-Disposition headers.
// Keep executable file types downloadable instead of opening them in our origin.
const playableType =
  /^(image\/(png|jpeg|gif|webp|avif|bmp|x-icon)|audio\/[\w.+-]+|video\/[\w.+-]+)$/i;
const safeBlob = blob =>
  playableType.test(blob.type)
    ? blob
    : new Blob([blob], { type: 'application/octet-stream' });

const failureState = async error => {
  const status = error.response?.status;
  if (status === 409) {
    let payload = error.response.data;
    try {
      if (typeof payload?.text === 'function') {
        payload = JSON.parse(await payload.text());
      }
    } catch {
      return 'unavailable';
    }
    if (payload?.code === 'attachment_scan_unavailable') return 'scan_pending';
  }
  return !status || status === 408 || status === 429 || status >= 500
    ? 'temporary_error'
    : 'unavailable';
};

export const useMessageAttachments = message => {
  const urls = ref({});
  const states = ref({});
  let controller;
  let revision = 0;

  const clear = () => {
    revision += 1;
    controller?.abort();
    Object.values(urls.value).forEach(url => URL.revokeObjectURL(url));
    urls.value = {};
    states.value = {};
  };

  const fetchAttachment = async attachment => {
    const { signal } = controller;
    const turn = revision;
    states.value = { ...states.value, [attachment.id]: 'loading' };
    try {
      const blob = await getProtectedAttachment({
        messageId: message.value.id,
        attachmentId: attachment.id,
        websiteToken: window.chatwootWebChannel.websiteToken,
        signal,
      });
      if (turn !== revision || signal.aborted) return;
      urls.value = {
        ...urls.value,
        [attachment.id]: URL.createObjectURL(safeBlob(blob)),
      };
      states.value = { ...states.value, [attachment.id]: 'ready' };
    } catch (error) {
      if (turn !== revision || signal.aborted) return;
      const state = await failureState(error);
      if (turn !== revision || signal.aborted) return;
      states.value = { ...states.value, [attachment.id]: state };
    }
  };

  const load = () => {
    clear();
    const attachments = message.value?.attachments || [];
    const protectedAttachments = attachments.filter(
      attachment => attachment.service_desk_protected === true
    );
    if (!protectedAttachments.length) return;
    if (!API.defaults.headers.common['X-Auth-Token']) {
      states.value = Object.fromEntries(
        protectedAttachments.map(attachment => [attachment.id, 'unavailable'])
      );
      return;
    }

    controller = new AbortController();
    protectedAttachments.forEach(fetchAttachment);
  };

  const retryAttachment = attachmentId => {
    if (
      !['scan_pending', 'temporary_error'].includes(states.value[attachmentId])
    ) {
      return;
    }
    const attachment = message.value?.attachments?.find(
      item => item.id === attachmentId && item.service_desk_protected === true
    );
    if (attachment && !controller.signal.aborted) fetchAttachment(attachment);
  };

  watch(
    [
      () => [message.value?.id, message.value?.attachments],
      widgetIdentityRevision,
    ],
    load,
    { deep: true, immediate: true, flush: 'sync' }
  );
  onBeforeUnmount(clear);

  const resolvedAttachments = computed(() =>
    (message.value?.attachments || []).map(attachment => {
      if (attachment.service_desk_protected !== true) return attachment;
      const url = urls.value[attachment.id];
      return {
        ...attachment,
        data_url: url || '',
        thumb_url: url || '',
        downloadState: states.value[attachment.id] || 'loading',
      };
    })
  );
  return { resolvedAttachments, retryAttachment };
};
