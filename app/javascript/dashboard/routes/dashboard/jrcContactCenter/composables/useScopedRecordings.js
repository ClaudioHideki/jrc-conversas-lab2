import { onBeforeUnmount, ref, watch } from 'vue';
import API from 'dashboard/api/jrcContactCenter';

// Native recording rows are intersected on the server. IDs and filters never grant access.
export const useScopedRecordings = ({
  accountId,
  actorScope,
  routeQuery,
  replaceQuery,
}) => {
  const items = ref([]);
  const meta = ref({ page: 1, per_page: 20, total: 0, pages: 0 });
  const period = ref(null);
  const summary = ref(null);
  const filters = ref({
    from: '',
    to: '',
    q: '',
    unit_id: '',
    queue_id: '',
    status: '',
    direction: '',
  });
  const page = ref(1);
  const capabilities = ref({});
  const loading = ref(false);
  const mediaLoading = ref(false);
  const error = ref('');
  const mediaError = ref('');
  const selected = ref(null);
  const url = ref('');
  let generation = 0;
  let mediaGeneration = 0;
  let controller;
  let downloadUrl = '';
  let mediaRevision = '';
  const clearMedia = () => {
    mediaGeneration += 1;
    controller?.abort();
    if (url.value) URL.revokeObjectURL(url.value);
    if (downloadUrl) URL.revokeObjectURL(downloadUrl);
    url.value = '';
    downloadUrl = '';
    mediaRevision = '';
    mediaLoading.value = false;
    mediaError.value = '';
  };
  const close = () => {
    clearMedia();
    selected.value = null;
  };
  const withdraw = () => {
    close();
    items.value = [];
    period.value = null;
    summary.value = null;
    capabilities.value = {};
  };
  const denied = failure => [401, 403, 404].includes(failure?.response?.status);
  const load = async () => {
    generation += 1;
    const version = generation;
    close();
    items.value = [];
    period.value = null;
    summary.value = null;
    error.value = '';
    loading.value = true;
    const account = String(accountId.value);
    try {
      const context = await API.context(account);
      if (version !== generation) return;
      if (
        String(context.data.account_id) !== account ||
        context.data.capabilities?.recordings_view !== true
      ) {
        withdraw();
        error.value = 'DENIED';
        return;
      }
      capabilities.value = context.data.capabilities;
      const response = await API.recordings(account, {
        ...filters.value,
        page: page.value,
        per_page: 20,
      });
      if (version !== generation) return;
      const data = response.data;
      if (
        String(data.account_id) !== account ||
        !Array.isArray(data.items) ||
        !data.meta ||
        !data.period
      )
        throw new Error('Invalid native recording list identity');
      const totals = data.summary;
      if (totals !== undefined) {
        const valid =
          totals?.duration_unit === 'seconds' &&
          Number.isSafeInteger(totals.total) &&
          totals.total === data.meta.total &&
          Number.isSafeInteger(totals.duration_measured_count) &&
          totals.duration_measured_count >= 0 &&
          Number.isSafeInteger(totals.duration_missing_count) &&
          totals.duration_missing_count >= 0 &&
          totals.duration_measured_count + totals.duration_missing_count ===
            totals.total &&
          (totals.duration_measured_count === 0
            ? totals.duration_seconds === null
            : Number.isSafeInteger(totals.duration_seconds) &&
              totals.duration_seconds >= 0);
        if (!valid)
          throw new TypeError('Invalid native recording period totals');
      }
      summary.value = totals ?? null;
      items.value = data.items;
      meta.value = data.meta;
      period.value = data.period;
    } catch (failure) {
      if (version !== generation) return;
      if (denied(failure)) withdraw();
      const invalidRange =
        failure?.response?.data?.error === 'invalid_recording_range';
      if (denied(failure)) error.value = 'DENIED';
      else error.value = invalidRange ? 'INVALID_RANGE' : 'ERROR';
    } finally {
      if (version === generation) loading.value = false;
    }
  };
  const select = async row => {
    close();
    const version = mediaGeneration;
    mediaLoading.value = true;
    try {
      const response = await API.recording(accountId.value, row.id);
      if (version !== mediaGeneration) return;
      const current = response.data.item;
      if (
        String(response.data.account_id) !== String(accountId.value) ||
        String(current?.id) !== String(row.id) ||
        current.call_session_id !== row.call_session_id
      )
        throw new Error('Changed native recording selection');
      selected.value = current;
    } catch (failure) {
      if (version !== mediaGeneration) return;
      if (denied(failure)) {
        withdraw();
        error.value = 'DENIED';
      } else mediaError.value = 'ERROR';
    } finally {
      if (version === mediaGeneration) mediaLoading.value = false;
    }
  };
  const bytes = async action => {
    if (!['playback', 'download'].includes(action)) return;
    const allowed =
      action === 'playback'
        ? capabilities.value.recordings_listen
        : capabilities.value.recordings_download;
    if (!allowed || !selected.value || mediaLoading.value) return;
    const current = selected.value;
    const version = mediaGeneration;
    const account = String(accountId.value);
    mediaLoading.value = true;
    mediaError.value = '';
    controller = new AbortController();
    if (action === 'playback' && url.value) {
      URL.revokeObjectURL(url.value);
      url.value = '';
    }
    try {
      const response = await API.recordingBytes(
        account,
        current.id,
        action,
        controller.signal
      );
      if (version !== mediaGeneration) return;
      const headers = response.headers;
      if (
        headers['x-jrc-recording-account'] !== account ||
        headers['x-jrc-recording-id'] !== String(current.id) ||
        headers['x-jrc-recording-call'] !== current.call_session_id ||
        !(response.data instanceof Blob) ||
        response.data.size <= 0 ||
        !response.data.type.startsWith('audio/') ||
        !/^[0-9a-f]{64}$/.test(headers['x-jrc-recording-revision'] || '')
      )
        throw new Error('Invalid private recording bytes');
      const disposition = headers['content-disposition'] || '';
      const filename =
        /\bfilename="(call-([0-9]+)\.(?:wav|mp3|ogg|webm|m4a|flac))"/.exec(
          disposition
        );
      if (
        action === 'download' &&
        (!disposition.startsWith('attachment;') ||
          filename?.[2] !== String(current.id))
      )
        throw new Error('Invalid native recording download identity');
      const created = URL.createObjectURL(response.data);
      if (action === 'playback') {
        if (url.value) URL.revokeObjectURL(url.value);
        mediaRevision = headers['x-jrc-recording-revision'];
        url.value = created;
      } else {
        if (downloadUrl) URL.revokeObjectURL(downloadUrl);
        downloadUrl = created;
        const link = document.createElement('a');
        link.href = created;
        link.download = filename[1];
        link.click();
      }
    } catch (failure) {
      if (version !== mediaGeneration) return;
      if (denied(failure)) {
        withdraw();
        error.value = 'DENIED';
      } else mediaError.value = 'MEDIA_ERROR';
    } finally {
      if (version === mediaGeneration) mediaLoading.value = false;
    }
  };
  const authorizePlayback = async () => {
    if (!url.value || !selected.value || !capabilities.value.recordings_listen)
      return false;
    const version = mediaGeneration;
    const account = String(accountId.value);
    const recording = String(selected.value.id);
    try {
      const request = crypto.randomUUID();
      const response = await API.recordingReproduction(account, recording, {
        request_id: request,
        source_revision: mediaRevision,
      });
      if (version !== mediaGeneration) return false;
      const data = response.data;
      if (
        String(data.account_id) !== account ||
        data.recording_id !== recording ||
        data.request_id !== request ||
        data.logged !== true
      )
        throw new Error('Invalid current recording reproduction receipt');
      return true;
    } catch (failure) {
      if (version !== mediaGeneration) return false;
      if (denied(failure)) {
        withdraw();
        error.value = 'DENIED';
      } else {
        clearMedia();
        mediaError.value = 'MEDIA_AUDIT_ERROR';
      }
      return false;
    }
  };
  const ownKeys = [
    'from',
    'to',
    'q',
    'unit_id',
    'queue_id',
    'status',
    'direction',
  ];
  const persist = async (criteria, targetPage) => {
    const query = { ...routeQuery.value };
    ownKeys.forEach(key => {
      const name = `recordings_${key}`;
      if (criteria[key]) query[name] = criteria[key];
      else delete query[name];
    });
    if (targetPage > 1) query.recordings_page = String(targetPage);
    else delete query.recordings_page;
    if (JSON.stringify(query) === JSON.stringify(routeQuery.value))
      return load();
    return replaceQuery(query);
  };
  const apply = () => persist(filters.value, 1);
  const clearFilters = () =>
    persist(
      {
        from: '',
        to: '',
        q: '',
        unit_id: '',
        queue_id: '',
        status: '',
        direction: '',
      },
      1
    );
  const changePage = value => {
    if (
      !Number.isSafeInteger(value) ||
      value < 1 ||
      value > meta.value.pages ||
      loading.value
    )
      return;
    persist(filters.value, value);
  };
  const playbackFailed = () => {
    clearMedia();
    mediaError.value = 'MEDIA_ERROR';
  };
  watch(
    [accountId, actorScope, routeQuery],
    () => {
      generation += 1;
      withdraw();
      try {
        const next = {};
        ownKeys.forEach(key => {
          const value = routeQuery.value[`recordings_${key}`] ?? '';
          if (typeof value !== 'string')
            throw new Error('Invalid recording query');
          next[key] = value;
        });
        const pageValue = routeQuery.value.recordings_page ?? '1';
        if (
          typeof pageValue !== 'string' ||
          !/^[1-9][0-9]{0,5}$/.test(pageValue)
        )
          throw new Error('Invalid recording page');
        filters.value = next;
        page.value = Number(pageValue);
        load();
      } catch {
        loading.value = false;
        error.value = 'ERROR';
      }
    },
    { immediate: true, deep: true, flush: 'sync' }
  );
  onBeforeUnmount(() => {
    generation += 1;
    withdraw();
  });
  return {
    items,
    meta,
    period,
    summary,
    filters,
    page,
    capabilities,
    loading,
    mediaLoading,
    error,
    mediaError,
    selected,
    url,
    load,
    apply,
    clearFilters,
    changePage,
    select,
    close,
    bytes,
    playbackFailed,
    authorizePlayback,
  };
};
