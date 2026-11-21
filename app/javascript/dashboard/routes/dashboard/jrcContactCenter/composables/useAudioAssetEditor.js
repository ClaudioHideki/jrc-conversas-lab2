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
  const copyVersion = shallowRef(null);
  const draft = ref({ name: '', description: '', purpose: '', folder_id: '' });
  const file = shallowRef(null);
  const sourceKind = ref('user_upload');
  const session = ref(0);
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
      sourceKind.value,
      copyVersion.value,
    ]);
  const reviewed = computed(() => reviewedDraft.value === fingerprint());
  const canSave = computed(() =>
    Boolean(
      canManage.value &&
        openedScope.value === scopeKey() &&
        !saving.value &&
        !opening.value &&
        error.value !== 'COPY_SOURCE_NOT_READY' &&
        reviewed.value &&
        revision.canSave.value &&
        (mode.value === 'edit' ||
          (mode.value === 'copy' && copyVersion.value) ||
          (file.value &&
            file.value.size > 0 &&
            file.value.size <= maxBytes.value)) &&
        (mode.value === 'replace' || draft.value.name.trim().length > 0)
    )
  );
  const close = () => {
    generation += 1;
    session.value += 1;
    selected.value = null;
    copyVersion.value = null;
    file.value = null;
    sourceKind.value = 'user_upload';
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
      if (nextMode === 'copy') {
        const source = record?.latest_version;
        if (
          record?.unit_id !== unitId.value ||
          source?.audio_asset_id !== record.id ||
          source?.unit_id !== unitId.value ||
          source?.technical_verification?.ready !== true ||
          !Number.isSafeInteger(source?.byte_size) ||
          source.byte_size <= 0 ||
          source.byte_size > maxBytes.value
        )
          throw new Error('Source requires a current native inspection');
        copyVersion.value = Object.freeze({
          id: source.id,
          sha256: source.sha256,
          byte_size: source.byte_size,
          number: source.number,
          file_name: source.file_name,
          source_kind: source.source_kind,
        });
        sourceKind.value = source.source_kind;
      }
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
    sourceKind.value = 'user_upload';
    reviewedDraft.value = '';
    error.value = '';
    if (!value) return;
    if (!value.size || value.size > maxBytes.value) {
      error.value = 'INVALID_FILE';
      return;
    }
    file.value = value;
  };
  const chooseCapturedFile = value => {
    if (submission.value || saving.value) return;
    chooseFile({ target: { files: [value] } });
    if (file.value) sourceKind.value = 'browser_capture';
  };
  const copyBody = () => {
    if (!submission.value)
      submission.value = Object.freeze({
        asset: Object.freeze({ ...draft.value }),
        source_version_id: copyVersion.value.id,
        idempotency_key: key,
      });
    return { ...submission.value, expected_revision: revision.state.expected };
  };
  const body = () => {
    if (!submission.value) {
      const form = new FormData();
      form.append('file', file.value);
      form.append('idempotency_key', key);
      form.append('source_kind', sourceKind.value);
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
      (!selected.value ||
        (mode.value === 'copy'
          ? item.id !== selected.value.id
          : item.id === selected.value.id));
    if (!valid) throw new Error('Invalid institutional audio receipt');
    if (mode.value === 'edit') return;
    const version = response.data?.received_version;
    if (
      !identity(version?.id) ||
      version.audio_asset_id !== item.id ||
      version.unit_id !== unitId.value ||
      !Number.isInteger(version.number) ||
      version.number < 1 ||
      version.source_kind !== sourceKind.value ||
      version.byte_size !==
        (mode.value === 'copy'
          ? copyVersion.value?.byte_size
          : file.value?.size) ||
      (mode.value === 'copy' &&
        (version.number !== 1 ||
          version.sha256 !== copyVersion.value?.sha256)) ||
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
      if (mode.value === 'copy')
        response = await API.duplicateAudioAsset(
          accountId.value,
          selected.value.id,
          copyBody()
        );
      else if (mode.value === 'edit')
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
      const copied = mode.value === 'copy' ? response.data.item : null;
      clear();
      if (copied) await onSaved(copied);
      else await onSaved();
    } catch (failure) {
      if (version !== generation) return;
      if ([401, 403, 404].includes(failure?.response?.status)) onDenied();
      else if (
        mode.value === 'copy' &&
        [
          'institutional_audio_not_verified',
          'institutional_audio_inspection_changed',
          'institutional_audio_read_limit_exceeded',
        ].includes(failure?.response?.data?.error)
      ) {
        submission.value = null;
        error.value = 'COPY_SOURCE_NOT_READY';
      } else if (
        [
          'invalid_institutional_audio_file',
          'unsupported_institutional_audio_file',
          'institutional_audio_invalid_codec',
          'institutional_audio_unsafe_file',
          'institutional_audio_integrity_failed',
        ].includes(failure?.response?.data?.error)
      ) {
        submission.value = null;
        file.value = null;
        error.value = 'INVALID_FILE';
      } else if (
        failure?.response?.status === 503 &&
        failure?.response?.data?.error ===
          'institutional_audio_inspection_unavailable'
      ) {
        submission.value = null;
        error.value = 'INSPECTION_UNAVAILABLE';
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
    copyVersion,
    draft,
    file,
    sourceKind,
    session,
    openedScope,
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
    chooseCapturedFile,
    save,
  };
};
