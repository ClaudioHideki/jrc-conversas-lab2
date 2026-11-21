import { computed, onBeforeUnmount, reactive, ref, watch } from 'vue';
import API from 'dashboard/api/jrcContactCenter';
import { validIvrAudioReference } from '../helpers/ivrDraft';

// Metadata selection only. Native draft writes and byte reads independently reauthorize every request.
export const useIvrAudioReference = ({ accountId, unitId, reference }) => {
  const choosing = ref(false);
  const pinned = ref(null);
  const candidate = ref(null);
  const error = ref('');
  const assets = reactive({
    items: [],
    page: 1,
    pages: 0,
    q: '',
    loading: false,
  });
  const versions = reactive({
    items: [],
    page: 1,
    pages: 0,
    assetId: '',
    loading: false,
  });
  let generation = 0;
  let assetRequest = 0;
  let versionRequest = 0;
  let pinnedRequest = 0;
  const busy = computed(() => assets.loading || versions.loading);
  const ready = row =>
    row?.technical_verification?.ready === true &&
    row.technical_verification.audio_version_id === row.id;
  const inUnit = row => String(row?.unit_id) === String(unitId.value);
  const versionReference = row => ({
    asset_id: row.audio_asset_id,
    version_id: row.id,
    sha256: row.sha256,
  });
  const validVersion = (row, assetId) =>
    inUnit(row) &&
    row.audio_asset_id === assetId &&
    validIvrAudioReference(versionReference(row));
  const reset = () => {
    generation += 1;
    choosing.value = false;
    pinned.value = null;
    candidate.value = null;
    error.value = '';
    Object.assign(assets, {
      items: [],
      page: 1,
      pages: 0,
      q: '',
      loading: false,
    });
    Object.assign(versions, {
      items: [],
      page: 1,
      pages: 0,
      assetId: '',
      loading: false,
    });
  };
  const denied = () => {
    reset();
    error.value = 'ERROR';
  };
  const checkPinned = async () => {
    pinnedRequest += 1;
    const own = pinnedRequest;
    const context = generation;
    pinned.value = null;
    error.value = '';
    const requested = reference.value && { ...reference.value };
    if (!requested || !unitId.value) return;
    try {
      if (!validIvrAudioReference(requested))
        throw new Error('Invalid local audio reference');
      const response = await API.audioVersion(
        accountId.value,
        requested.asset_id,
        requested.version_id
      );
      if (context !== generation || own !== pinnedRequest) return;
      const row = response.data.item;
      if (
        !validVersion(row, requested.asset_id) ||
        row.id !== requested.version_id ||
        row.sha256 !== requested.sha256 ||
        !ready(row)
      )
        throw new Error('Unavailable local audio reference');
      pinned.value = row;
    } catch {
      if (context === generation && own === pinnedRequest)
        error.value = 'UNAVAILABLE';
    }
  };
  const loadAssets = async (page = 1) => {
    if (!unitId.value) return;
    assetRequest += 1;
    const own = assetRequest;
    const context = generation;
    assets.loading = true;
    assets.items = [];
    assets.pages = 0;
    error.value = '';
    try {
      const { data } = await API.audioAssets(accountId.value, {
        unit_id: unitId.value,
        q: assets.q,
        page,
        per_page: 20,
      });
      if (context !== generation || own !== assetRequest) return;
      if (!data.items.every(inUnit))
        throw new Error('Invalid audio unit response');
      Object.assign(assets, {
        items: data.items,
        page: data.meta.page,
        pages: data.meta.pages,
      });
    } catch {
      if (context === generation && own === assetRequest) denied();
    } finally {
      if (context === generation && own === assetRequest)
        assets.loading = false;
    }
  };
  const loadVersions = async (assetId, page = 1) => {
    versionRequest += 1;
    const own = versionRequest;
    const context = generation;
    candidate.value = null;
    Object.assign(versions, { items: [], pages: 0, assetId, loading: false });
    if (!assetId) return;
    versions.loading = true;
    error.value = '';
    try {
      const { data } = await API.audioVersions(accountId.value, assetId, {
        page,
        per_page: 20,
      });
      if (context !== generation || own !== versionRequest) return;
      if (!data.items.every(row => validVersion(row, assetId)))
        throw new Error('Invalid audio versions response');
      Object.assign(versions, {
        items: data.items,
        page: data.meta.page,
        pages: data.meta.pages,
      });
    } catch {
      if (context === generation && own === versionRequest) denied();
    } finally {
      if (context === generation && own === versionRequest)
        versions.loading = false;
    }
  };
  const begin = () => {
    choosing.value = true;
    candidate.value = null;
    loadAssets();
  };
  const cancel = () => {
    generation += 1;
    choosing.value = false;
    candidate.value = null;
    assets.items = [];
    assets.loading = false;
    versions.items = [];
    versions.assetId = '';
    versions.loading = false;
  };
  const select = id => {
    candidate.value =
      versions.items.find(row => row.id === id && ready(row)) || null;
  };
  watch(
    [accountId, unitId],
    () => {
      reset();
      checkPinned();
    },
    { immediate: true }
  );
  watch(
    reference,
    () => {
      cancel();
      checkPinned();
    },
    { deep: true }
  );
  onBeforeUnmount(reset);
  return {
    choosing,
    pinned,
    candidate,
    error,
    assets,
    versions,
    busy,
    ready,
    begin,
    cancel,
    select,
    loadAssets,
    loadVersions,
    checkPinned,
    denied,
    versionReference,
  };
};
