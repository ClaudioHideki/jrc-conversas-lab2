import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, h, ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import { useScopedRecordings } from './useScopedRecordings';
import RecordingsPage from '../views/RecordingsPage.vue';

const nativeStore = vi.hoisted(() => ({
  user: undefined,
  routeReplacements: [],
  route: { params: { accountId: '1' }, query: {} },
}));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => nativeStore.user,
}));
vi.mock('vue-router', () => ({
  useRoute: () => nativeStore.route,
  useRouter: () => ({
    replace: vi.fn(value => nativeStore.routeReplacements.push(value)),
  }),
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: {
    context: vi.fn(),
    recordings: vi.fn(),
    recording: vi.fn(),
    recordingBytes: vi.fn(),
    recordingReproduction: vi.fn(),
    units: vi.fn(),
    queues: vi.fn(),
  },
}));
const wrappers = [];
const row = {
  id: 11,
  call_session_id: '7',
  unique_id: 'SYNTHETIC call',
  recording_state: 'requestable',
};
const context = () => ({
  data: {
    account_id: '1',
    capabilities: {
      recordings_view: true,
      recordings_listen: true,
      recordings_download: false,
    },
  },
});
const page = (items = [row]) => ({
  data: {
    account_id: '1',
    items,
    meta: { page: 1, per_page: 20, pages: 3, total: 41 },
    period: {
      from: '2026-11-20',
      to: '2026-11-26',
      timezone: 'America/Sao_Paulo',
    },
  },
});
const bytes = () => ({
  data: new Blob(['SYNTHETIC audio bytes'], { type: 'audio/wav' }),
  headers: {
    'x-jrc-recording-account': '1',
    'x-jrc-recording-id': '11',
    'x-jrc-recording-call': '7',
    'x-jrc-recording-revision': 'a'.repeat(64),
  },
});
const fixture = (initialQuery = {}) => {
  const accountId = ref('1');
  const actorScope = ref('synthetic-agent');
  const routeQuery = ref({ preserved_other_module: 'yes', ...initialQuery });
  const replaceQuery = async value => {
    routeQuery.value = value;
  };
  let state;
  const wrapper = mount(
    defineComponent({
      setup() {
        state = useScopedRecordings({
          accountId,
          actorScope,
          routeQuery,
          replaceQuery,
        });
        return () => h('div');
      },
    })
  );
  wrappers.push(wrapper);
  return { wrapper, state, accountId, actorScope, routeQuery };
};
beforeEach(() => {
  vi.clearAllMocks();
  nativeStore.routeReplacements = [];
  API.context.mockResolvedValue(context());
  API.recordings.mockResolvedValue(page());
  API.recording.mockResolvedValue({
    data: { account_id: '1', item: { ...row } },
  });
  API.recordingBytes.mockResolvedValue(bytes());
  vi.stubGlobal('crypto', {
    randomUUID: vi.fn(() => '11111111-1111-4111-8111-111111111111'),
  });
  API.recordingReproduction.mockImplementation(
    async (account, recording, body) => ({
      data: {
        account_id: account,
        recording_id: recording,
        request_id: body.request_id,
        logged: true,
      },
    })
  );
  const Original = URL;
  vi.stubGlobal(
    'URL',
    class extends Original {
      static createObjectURL = vi.fn(() => 'blob:synthetic-recording');

      static revokeObjectURL = vi.fn();
    }
  );
  vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(() => {});
});
afterEach(() => {
  wrappers.splice(0).forEach(wrapper => wrapper.unmount());
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

// Boundary-mocked Vue checks, not provider, Rails or browser acceptance.
describe('current-scope recording browser state', () => {
  it('uses current native capabilities and scoped server totals instead of fabricated metrics', async () => {
    const { state } = fixture();
    await flushPromises();
    expect(state.items.value).toEqual([row]);
    expect(state.meta.value.total).toBe(41);
    expect(state.period.value.timezone).toBe('America/Sao_Paulo');
    expect(API.recordings).toHaveBeenCalledWith(
      '1',
      expect.objectContaining({ page: 1, per_page: 20 })
    );
    expect(API.recordingBytes).not.toHaveBeenCalled();
  });
  it('does not infer recording authority from an administrator profile or foreign native account response', async () => {
    API.context.mockResolvedValueOnce({
      data: {
        account_id: '1',
        capabilities: { configure: true, administer: true },
      },
    });
    const { state } = fixture();
    await flushPromises();
    expect(state.error.value).toBe('DENIED');
    expect(API.recordings).not.toHaveBeenCalled();
    API.context.mockResolvedValueOnce({
      data: { ...context().data, account_id: '2' },
    });
    await state.load();
    expect(state.error.value).toBe('DENIED');
    expect(API.recordings).not.toHaveBeenCalled();
  });
  it('shows a list failure without converting missing reports into an empty successful result', async () => {
    API.recordings.mockRejectedValueOnce({ response: { status: 503 } });
    const { state } = fixture();
    await flushPromises();
    expect(state.error.value).toBe('ERROR');
    expect(state.items.value).toEqual([]);
    expect(state.period.value).toBeNull();
    API.recordings.mockRejectedValueOnce({
      response: { status: 422, data: { error: 'invalid_recording_range' } },
    });
    await state.load();
    expect(state.error.value).toBe('INVALID_RANGE');
    expect(state.items.value).toEqual([]);
  });
  it('preserves filters on pagination and removes every explicit criterion only when requested', async () => {
    const { state } = fixture();
    await flushPromises();
    state.filters.value = {
      from: '2026-11-01',
      to: '2026-11-15',
      q: 'SYNTHETIC',
      unit_id: '4',
      queue_id: '5',
    };
    await state.apply();
    await flushPromises();
    state.changePage(2);
    await flushPromises();
    expect(API.recordings).toHaveBeenLastCalledWith('1', {
      ...state.filters.value,
      page: 2,
      per_page: 20,
    });
    await state.clearFilters();
    await flushPromises();
    expect(state.page.value).toBe(1);
    expect(API.recordings).toHaveBeenLastCalledWith('1', {
      from: '',
      to: '',
      q: '',
      unit_id: '',
      queue_id: '',
      page: 1,
      per_page: 20,
    });
  });
  it('restores the selected native page and criteria from the URL while preserving unrelated navigation context', async () => {
    const { state, routeQuery } = fixture({
      recordings_from: '2026-11-01',
      recordings_to: '2026-11-15',
      recordings_unit_id: '4',
      recordings_page: '2',
    });
    await flushPromises();
    expect(API.recordings).toHaveBeenCalledWith(
      '1',
      expect.objectContaining({
        from: '2026-11-01',
        to: '2026-11-15',
        unit_id: '4',
        page: 2,
      })
    );
    await state.clearFilters();
    await flushPromises();
    expect(routeQuery.value).toEqual({ preserved_other_module: 'yes' });
    expect(state.page.value).toBe(1);
  });

  it('rejects ambiguous multi-valued recording URL criteria instead of silently querying a broader list', async () => {
    const { state } = fixture({ recordings_unit_id: ['4', '5'] });
    await flushPromises();
    expect(state.error.value).toBe('ERROR');
    expect(state.items.value).toEqual([]);
    expect(API.context).not.toHaveBeenCalled();
    expect(API.recordings).not.toHaveBeenCalled();
  });

  it('does not restore a slower earlier list after account switching', async () => {
    let finish;
    API.recordings.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const { state, accountId } = fixture();
    await flushPromises();
    API.context.mockResolvedValueOnce({
      data: { ...context().data, account_id: '2' },
    });
    API.recordings.mockResolvedValueOnce({
      data: { ...page([]).data, account_id: '2' },
    });
    accountId.value = '2';
    await flushPromises();
    finish(page());
    await flushPromises();
    expect(state.items.value).toEqual([]);
    expect(state.error.value).toBe('');
  });
  it('fetches current detail metadata before offering media without requesting bytes implicitly', async () => {
    const { state } = fixture();
    await flushPromises();
    await state.select(row);
    expect(API.recording).toHaveBeenCalledWith('1', 11);
    expect(state.selected.value).toEqual(row);
    expect(API.recordingBytes).not.toHaveBeenCalled();
  });
  it('rejects a changed call identity under the same displayed recording identifier', async () => {
    API.recording.mockResolvedValueOnce({
      data: { account_id: '1', item: { ...row, call_session_id: '8' } },
    });
    const { state } = fixture();
    await flushPromises();
    await state.select(row);
    expect(state.selected.value).toBeNull();
    expect(state.mediaError.value).toBe('ERROR');
    expect(API.recordingBytes).not.toHaveBeenCalled();
  });
  it('binds media to exact account recording and call headers before making a local blob URL', async () => {
    const { state } = fixture();
    await flushPromises();
    await state.select(row);
    await state.bytes('playback');
    expect(API.recordingBytes).toHaveBeenCalledWith(
      '1',
      11,
      'playback',
      expect.any(AbortSignal)
    );
    expect(state.url.value).toBe('blob:synthetic-recording');
    expect(URL.createObjectURL).toHaveBeenCalledOnce();
    state.close();
    expect(URL.revokeObjectURL).toHaveBeenCalledWith(
      'blob:synthetic-recording'
    );
  });
  it('rejects successful HTTP bytes from another scope instead of displaying or downloading them', async () => {
    const response = bytes();
    response.headers['x-jrc-recording-account'] = '2';
    API.recordingBytes.mockResolvedValueOnce(response);
    const { state } = fixture();
    await flushPromises();
    await state.select(row);
    await state.bytes('playback');
    expect(state.url.value).toBe('');
    expect(URL.createObjectURL).not.toHaveBeenCalled();
    expect(state.mediaError.value).toBe('MEDIA_ERROR');
    expect(state.selected.value).toEqual(row);
  });
  it('keeps the selected metadata for a recoverable media failure without inventing a successful player', async () => {
    const { state } = fixture();
    await flushPromises();
    await state.select(row);
    await state.bytes('playback');
    expect(state.url.value).toBe('blob:synthetic-recording');
    API.recordingBytes.mockRejectedValueOnce({ response: { status: 504 } });
    await state.bytes('playback');
    expect(URL.revokeObjectURL).toHaveBeenCalledWith(
      'blob:synthetic-recording'
    );
    expect(state.selected.value).toEqual(row);
    expect(state.url.value).toBe('');
    expect(state.mediaError.value).toBe('MEDIA_ERROR');
  });
  it('rejects an unrelated download filename even when the returned account and call headers match', async () => {
    const reply = bytes();
    reply.headers['content-disposition'] =
      'attachment; filename="call-999.wav"';
    API.recordingBytes.mockResolvedValueOnce(reply);
    const { state } = fixture();
    await flushPromises();
    await state.select(row);
    state.capabilities.value.recordings_download = true;
    await state.bytes('download');
    expect(HTMLAnchorElement.prototype.click).not.toHaveBeenCalled();
    expect(URL.createObjectURL).not.toHaveBeenCalled();
    expect(state.mediaError.value).toBe('MEDIA_ERROR');
    expect(state.selected.value).toEqual(row);
  });

  it('uses the separate freshly authorized download endpoint and never treats listen authority as download', async () => {
    const { state } = fixture();
    await flushPromises();
    await state.select(row);
    await state.bytes('download');
    expect(API.recordingBytes).not.toHaveBeenCalled();
    state.capabilities.value = {
      ...state.capabilities.value,
      recordings_download: true,
    };
    const download = bytes();
    download.headers['content-disposition'] =
      'attachment; filename="call-11.wav"';
    API.recordingBytes.mockResolvedValueOnce(download);
    await state.bytes('download');
    expect(API.recordingBytes).toHaveBeenCalledWith(
      '1',
      11,
      'download',
      expect.any(AbortSignal)
    );
    expect(HTMLAnchorElement.prototype.click).toHaveBeenCalledOnce();
    expect(state.url.value).toBe('');
  });
  it('withdraws private media synchronously on a profile change and rejects a delayed byte response', async () => {
    let finish;
    API.recordingBytes.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const { state, actorScope } = fixture();
    await flushPromises();
    await state.select(row);
    const pending = state.bytes('playback');
    actorScope.value = 'synthetic-revoked-profile';
    expect(state.selected.value).toBeNull();
    expect(state.items.value).toEqual([]);
    finish(bytes());
    await pending;
    expect(URL.createObjectURL).not.toHaveBeenCalled();
  });
  it('forgets the old selection and bytes when current server permission is denied', async () => {
    const { state } = fixture();
    await flushPromises();
    await state.select(row);
    await state.bytes('playback');
    API.recordingBytes.mockRejectedValueOnce({ response: { status: 403 } });
    await state.bytes('playback');
    expect(state.selected.value).toBeNull();
    expect(state.url.value).toBe('');
    expect(state.items.value).toEqual([]);
    expect(state.error.value).toBe('DENIED');
    expect(URL.revokeObjectURL).toHaveBeenCalledWith(
      'blob:synthetic-recording'
    );
  });

  it('discards native unit and queue labels from the previous profile in the actual recording page', async () => {
    nativeStore.user = ref({
      id: 7,
      accounts: [
        {
          id: 1,
          role: 'agent',
          contact_center_eligible: true,
          permissions: [
            'jrc_contact_center_recordings_view',
            'jrc_contact_center_recordings_listen',
          ],
        },
      ],
    });
    API.units.mockResolvedValue({
      data: {
        items: [{ id: 21, name: 'SYNTHETIC previously covered unit' }],
        meta: { pages: 1 },
      },
    });
    API.queues.mockResolvedValue({
      data: {
        items: [{ id: 31, name: 'SYNTHETIC previously covered queue' }],
        meta: { pages: 1 },
      },
    });
    const wrapper = mount(RecordingsPage, {
      global: { stubs: { Icon: true, CallRecordingPlayer: true } },
    });
    wrappers.push(wrapper);
    await flushPromises();
    expect(wrapper.text()).toContain('SYNTHETIC previously covered unit');
    expect(wrapper.text()).toContain('SYNTHETIC previously covered queue');
    API.units.mockRejectedValue({ response: { status: 403 } });
    API.queues.mockRejectedValue({ response: { status: 403 } });
    API.recordings.mockResolvedValue(page([]));
    nativeStore.user.value = {
      id: 7,
      accounts: [
        {
          id: 1,
          role: 'agent',
          contact_center_eligible: true,
          permissions: ['jrc_contact_center_recordings_view'],
        },
      ],
    };
    await flushPromises();
    expect(API.units).toHaveBeenCalledTimes(2);
    expect(API.queues).toHaveBeenCalledTimes(2);
    expect(wrapper.text()).not.toContain('SYNTHETIC previously covered unit');
    expect(wrapper.text()).not.toContain('SYNTHETIC previously covered queue');
    expect(
      wrapper
        .findAll('[data-acw-rule-target] select option')
        .map(option => option.attributes('value'))
    ).toEqual(['', '']);
  });
  it('keeps a usable previous-page action when authorized results shrink below the bookmarked page', async () => {
    nativeStore.user = ref({ id: 7, accounts: [] });
    nativeStore.route = {
      params: { accountId: '1' },
      query: { recordings_page: '2' },
    };
    const empty = page([]);
    empty.data.meta = { page: 2, pages: 1, per_page: 20, total: 20 };
    API.recordings.mockResolvedValue(empty);
    API.units.mockResolvedValue({ data: { items: [], meta: { pages: 1 } } });
    API.queues.mockResolvedValue({ data: { items: [], meta: { pages: 1 } } });
    const wrapper = mount(RecordingsPage, {
      global: { stubs: { Icon: true } },
    });
    wrappers.push(wrapper);
    await flushPromises();
    const navigation = wrapper.get('nav');
    const buttons = navigation.findAll('button');
    expect(buttons[0].text()).toBe('JRC_CONTACT_CENTER.RECORDINGS.PREVIOUS');
    expect(buttons[0].element.disabled).toBe(false);
    expect(buttons[1].element.disabled).toBe(true);
    await buttons[0].trigger('click');
    expect(nativeStore.routeReplacements).toEqual([{ query: {} }]);
  });
  it('records each actual playback start with a distinct key and the current media source revision', async () => {
    const { state } = fixture();
    await flushPromises();
    await state.select(row);
    await state.bytes('playback');
    crypto.randomUUID.mockReturnValueOnce(
      '11111111-1111-4111-8111-111111111111'
    );
    crypto.randomUUID.mockReturnValueOnce(
      '22222222-2222-4222-8222-222222222222'
    );
    await state.authorizePlayback();
    await state.authorizePlayback();
    expect(API.recordingReproduction).toHaveBeenCalledTimes(2);
    expect(
      API.recordingReproduction.mock.calls.map(call => call[2].request_id)
    ).toEqual([
      '11111111-1111-4111-8111-111111111111',
      '22222222-2222-4222-8222-222222222222',
    ]);
    expect(
      API.recordingReproduction.mock.calls.every(
        call =>
          call[0] === '1' &&
          call[1] === '11' &&
          call[2].source_revision === 'a'.repeat(64)
      )
    ).toBe(true);
    expect(state.url.value).toBe('blob:synthetic-recording');
  });

  it('withdraws playable bytes and shows an explicit error when the required audit cannot be persisted', async () => {
    const { state } = fixture();
    await flushPromises();
    await state.select(row);
    await state.bytes('playback');
    API.recordingReproduction.mockRejectedValueOnce({
      response: { status: 500 },
    });
    await state.authorizePlayback();
    expect(state.url.value).toBe('');
    expect(state.selected.value).toEqual(row);
    expect(state.mediaError.value).toBe('MEDIA_AUDIT_ERROR');
    expect(URL.revokeObjectURL).toHaveBeenCalledWith(
      'blob:synthetic-recording'
    );
  });

  it('withdraws the former recording and metadata when listening authorization is revoked after byte delivery', async () => {
    const { state } = fixture();
    await flushPromises();
    await state.select(row);
    await state.bytes('playback');
    API.recordingReproduction.mockRejectedValueOnce({
      response: { status: 401 },
    });
    await state.authorizePlayback();
    expect(state.url.value).toBe('');
    expect(state.selected.value).toBeNull();
    expect(state.items.value).toEqual([]);
    expect(state.error.value).toBe('DENIED');
  });
  it('renders one semantic recording table with the native authorized rows and explicit metadata columns', async () => {
    nativeStore.user = ref({ id: 7, accounts: [] });
    nativeStore.route = { params: { accountId: '1' }, query: {} };
    API.units.mockResolvedValue({ data: { items: [], meta: { pages: 1 } } });
    API.queues.mockResolvedValue({ data: { items: [], meta: { pages: 1 } } });
    const wrapper = mount(RecordingsPage, {
      global: { stubs: { Icon: true } },
    });
    wrappers.push(wrapper);
    await flushPromises();
    const table = wrapper.get('[data-recordings-table]');
    expect(table.element.tagName).toBe('TABLE');
    expect(table.findAll('thead th[scope="col"]')).toHaveLength(7);
    expect(table.findAll('[data-recording-row]')).toHaveLength(1);
    expect(
      table.get('[data-recording-row]').attributes('data-recording-row')
    ).toBe(String(row.id));
    expect(table.text()).not.toContain('recording_reference');
    expect(API.recordingBytes).not.toHaveBeenCalled();
  });
});
