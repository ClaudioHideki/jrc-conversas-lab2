import { computed, onBeforeUnmount, ref, shallowRef, watch } from 'vue';
import API from 'dashboard/api/jrcContactCenter';
import { useConfigurationRevision } from './useConfigurationRevision';

export const useAudioAssetEditor = ({
  accountId,
  unitId,
  folderId,
  canManage,
  maxBytes,
  onSaved,
  onDenied,
}) => {
  const dialog = ref(null);
  const mode = ref('upload');
  const selected = ref(null);
  const draft = ref({ name: '', description: '', purpose: '', folder_id: '' });
  const file = shallowRef(null);
  const submission = shallowRef(null);
  const saving = ref(false);
  const opening = ref(false);
  const error = ref('');
  const reviewedDraft = ref('');
  let generation = 0;
  let key = '';
  const scopeKey = () =>
    JSON.stringify([String(accountId.value), unitId.value, folderId.value]);
  const openedScope = ref('');
  const revision = useConfigurationRevision({
    accountId,
    resource: computed(() => 'audio_assets'),
    draft,
    onDenied,
  });
  const fingerprint = () =>
    JSON.stringify([
      draft.value,
      file.value?.name,
      file.value?.size,
      file.value?.lastModified,
    ]);
  const reviewed = computed(() => reviewedDraft.value === fingerprint());
  const canSave = computed(() =>
    Boolean(
      canManage.value &&
        openedScope.value === scopeKey() &&
        !saving.value &&
        !opening.value &&
        reviewed.value &&
        revision.canSave.value &&
        (mode.value === 'edit' ||
          (file.value &&
            file.value.size > 0 &&
            file.value.size <= maxBytes.value)) &&
        (mode.value === 'replace' || draft.value.name.trim().length > 0)
    )
  );
  const close = () => {
    generation += 1;
    selected.value = null;
    file.value = null;
    submission.value = null;
    draft.value = { name: '', description: '', purpose: '', folder_id: '' };
    reviewedDraft.value = '';
    saving.value = false;
    opening.value = false;
    error.value = '';
    key = '';
    openedScope.value = '';
    revision.capture(null);
  };
  const clear = () => {
    dialog.value?.close();
    close();
  };
  const open = async (nextMode, row) => {
    if (!canManage.value || saving.value || opening.value) return;
    close();
    const version = generation;
    const origin = scopeKey();
    opening.value = true;
    try {
      const record = row
        ? (await API.audioAsset(accountId.value, row.id)).data.item
        : null;
      if (version !== generation || origin !== scopeKey()) return;
      mode.value = nextMode;
      selected.value = record;
      draft.value = {
        name: record?.name || '',
        description: record?.description || '',
        purpose: record?.purpose || '',
        folder_id: record ? record.folder_id || '' : folderId.value || '',
      };
      key = crypto.randomUUID();
      openedScope.value = origin;
      revision.capture(record);
      dialog.value.open();
    } catch (failure) {
      if (version === generation) {
        if ([401, 403, 404].includes(failure?.response?.status)) onDenied();
        else error.value = 'ERROR';
      }
    } finally {
      if (version === generation) opening.value = false;
    }
  };
  const chooseFile = event => {
    if (submission.value || saving.value) return;
    const value = event.target.files?.[0];
    file.value = null;
    reviewedDraft.value = '';
    error.value = '';
    if (!value) return;
    if (!value.size || value.size > maxBytes.value) {
      error.value = 'INVALID_FILE';
      return;
    }
    file.value = value;
  };
  const body = () => {
    if (!submission.value) {
      const form = new FormData();
      form.append('file', file.value);
      form.append('idempotency_key', key);
      if (mode.value === 'upload') {
        form.append('unit_id', unitId.value);
        Object.entries(draft.value).forEach(([name, value]) =>
          form.append(`asset[${name}]`, value)
        );
      }
      submission.value = form;
    }
    if (mode.value === 'replace')
      submission.value.set('expected_revision', revision.state.expected);
    return submission.value;
  };
  const savedReceipt = response => {
    const item = response.data?.item;
    const identity = value =>
      typeof value === 'string' && /^[1-9]\d{0,18}$/.test(value);
    const valid =
      String(response.data?.account_id) === String(accountId.value) &&
      identity(item?.id) &&
      item.unit_id === unitId.value &&
      typeof item.revision === 'string' &&
      /^[a-f0-9]{64}$/.test(item.revision) &&
      (!selected.value || item.id === selected.value.id);
    if (!valid) throw new Error('Invalid institutional audio receipt');
    if (mode.value === 'edit') return;
    const version = response.data?.received_version;
    if (
      !identity(version?.id) ||
      version.audio_asset_id !== item.id ||
      version.unit_id !== unitId.value ||
      !Number.isInteger(version.number) ||
      version.number < 1 ||
      version.byte_size !== file.value?.size ||
      typeof version.sha256 !== 'string' ||
      !/^[a-f0-9]{64}$/.test(version.sha256)
    )
      throw new Error('Invalid institutional audio version receipt');
  };
  const save = async () => {
    if (!canSave.value) return;
    const version = generation;
    saving.value = true;
    error.value = '';
    try {
      let response;
      if (mode.value === 'edit')
        response = await API.updateAudioAsset(
          accountId.value,
          selected.value.id,
          draft.value,
          revision.options()
        );
      else if (mode.value === 'replace')
        response = await API.receiveAudioVersion(
          accountId.value,
          selected.value.id,
          body()
        );
      else response = await API.receiveAudioAsset(accountId.value, body());
      if (version !== generation) return;
      savedReceipt(response);
      clear();
      await onSaved();
    } catch (failure) {
      if (version !== generation) return;
      if ([401, 403, 404].includes(failure?.response?.status)) onDenied();
      else if (
        [
          'invalid_institutional_audio_file',
          'unsupported_institutional_audio_file',
        ].includes(failure?.response?.data?.error)
      ) {
        submission.value = null;
        file.value = null;
        error.value = 'INVALID_FILE';
      } else if (!revision.handleError(failure))
        error.value = submission.value ? 'RECEIPT_ERROR' : 'SAVE_ERROR';
      reviewedDraft.value = '';
    } finally {
      if (version === generation) saving.value = false;
    }
  };
  watch([accountId, unitId, folderId, canManage], clear);
  onBeforeUnmount(close);
  return {
    dialog,
    mode,
    selected,
    draft,
    file,
    submission,
    saving,
    opening,
    error,
    reviewedDraft,
    revision,
    reviewed,
    fingerprint,
    canSave,
    open,
    close,
    clear,
    chooseFile,
    save,
  };
};
