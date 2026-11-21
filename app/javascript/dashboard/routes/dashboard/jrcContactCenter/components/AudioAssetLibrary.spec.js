import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { computed, defineComponent, reactive, ref } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import AudioAssetLibrary from './AudioAssetLibrary.vue';
import AudioInspectionHistory from './AudioInspectionHistory.vue';
import AudioCaptureDraft from './AudioCaptureDraft.vue';

const mocks = vi.hoisted(() => ({ route: null, replace: vi.fn(), user: null }));
vi.mock('vue-router', () => ({
  useRoute: () => mocks.route,
  useRouter: () => ({ replace: mocks.replace }),
}));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => mocks.user,
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: {
    audioAssets: vi.fn(),
    audioAsset: vi.fn(),
    audioVersions: vi.fn(),
    duplicateAudioAsset: vi.fn(),
    updateAudioAsset: vi.fn(),
    receiveAudioAsset: vi.fn(),
    receiveAudioVersion: vi.fn(),
    configurationRecord: vi.fn(),
  },
}));
const Dialog = defineComponent({
  props: { disableConfirmButton: Boolean },
  emits: ['confirm', 'close'],
  setup(props, { expose, emit }) {
    const visible = ref(false);
    expose({
      open: () => {
        visible.value = true;
      },
      close: () => {
        visible.value = false;
        emit('close');
      },
    });
    return {
      visible,
      disabled: computed(() => props.disableConfirmButton),
      confirm: () => emit('confirm'),
    };
  },
  template:
    '<form v-if="visible" role="dialog" @submit.prevent="confirm"><slot /><button type="submit" data-submit :disabled="disabled"></button></form>',
});
const row = {
  id: '44',
  unit_id: '10',
  name: 'SYNTHETIC private message',
  description: 'SYNTHETIC description',
  folder_id: null,
  revision: 'a'.repeat(64),
  latest_version: {
    id: '90',
    audio_asset_id: '44',
    unit_id: '10',
    number: 2,
    file_name: 'SYNTHETIC.wav',
    content_type: 'audio/wav',
    sha256: 'f'.repeat(64),
    byte_size: 60,
    ready: false,
    security_state: 'not_verified',
  },
};
const context = {
  capabilities: { configure: true },
  units: [{ id: '10' }, { id: '11' }],
};
const fixture = (stubs = {}) =>
  mount(AudioAssetLibrary, {
    props: { accountId: '1', unitId: '10', folderId: '', context },
    global: { stubs: { Dialog, AudioFolderPicker: true, ...stubs } },
  });
enableAutoUnmount(afterEach);
beforeEach(() => {
  vi.clearAllMocks();
  mocks.route = reactive({ query: {} });
  mocks.user = ref({
    id: 7,
    accounts: [
      {
        id: 1,
        role: 'administrator',
        permissions: ['jrc_contact_center_configure'],
      },
    ],
  });
  API.audioAssets.mockResolvedValue({
    data: {
      items: [structuredClone(row)],
      meta: { page: 1, pages: 2, total: 21 },
      max_upload_bytes: 1000,
    },
  });
  API.audioAsset.mockResolvedValue({
    data: { account_id: '1', item: structuredClone(row) },
  });
  API.updateAudioAsset.mockResolvedValue({
    data: { account_id: '1', item: row },
  });
  API.audioVersions.mockResolvedValue({
    data: {
      items: [
        {
          ...row.latest_version,
          id: '90',
          created_by_name: 'SYNTHETIC creator',
          sha256: 'f'.repeat(64),
        },
      ],
      meta: { page: 1, pages: 1, total: 1 },
    },
  });
});

describe('unit scoped private audio metadata UI', () => {
  it('keeps duplication disabled for a quarantined file instead of presenting it as technically ready', async () => {
    const wrapper = fixture();
    await flushPromises();
    expect(wrapper.get('[data-copy-audio-asset="44"]').element.disabled).toBe(
      true
    );
    expect(API.duplicateAudioAsset).not.toHaveBeenCalled();
    expect(wrapper.find('[data-audio-copy-source]').exists()).toBe(false);
  });

  it('opens the existing reviewed editor in copy mode with pinned metadata and no upload or microphone controls', async () => {
    const item = structuredClone(row);
    item.latest_version.technical_verification = { ready: true };
    item.latest_version.source_kind = 'user_upload';
    API.audioAssets.mockResolvedValueOnce({
      data: {
        items: [item],
        meta: { total: 1, pages: 1 },
        max_upload_bytes: 1000,
      },
    });
    API.audioAsset.mockResolvedValueOnce({ data: { account_id: '1', item } });
    const wrapper = fixture();
    await flushPromises();
    await wrapper.get('[data-copy-audio-asset="44"]').trigger('click');
    await flushPromises();
    expect(wrapper.get('[data-audio-copy-source]').text()).toContain(
      item.latest_version.sha256
    );
    expect(wrapper.find('[data-audio-asset-file]').exists()).toBe(false);
    expect(wrapper.find('[data-audio-source-capture]').exists()).toBe(false);
    expect(wrapper.find('[data-audio-asset-name]').exists()).toBe(true);
    expect(wrapper.get('[data-submit]').element.disabled).toBe(true);
    expect(API.duplicateAudioAsset).not.toHaveBeenCalled();
    await wrapper
      .get('[data-audio-asset-name]')
      .setValue('SYNTHETIC copy outside old filter');
    await wrapper.get('[data-review-audio-asset]').setValue(true);
    API.duplicateAudioAsset.mockResolvedValueOnce({
      data: {
        account_id: '1',
        item: {
          ...item,
          id: '45',
          name: 'SYNTHETIC copy outside old filter',
          revision: 'b'.repeat(64),
          latest_version: {
            ...item.latest_version,
            id: '91',
            audio_asset_id: '45',
            number: 1,
          },
        },
        received_version: {
          ...item.latest_version,
          id: '91',
          audio_asset_id: '45',
          number: 1,
        },
      },
    });
    await wrapper.get('[role="dialog"]').trigger('submit');
    await flushPromises();
    expect(wrapper.get('[data-audio-copy-receipt="45"]').exists()).toBe(true);
    await wrapper.get('[data-open-copied-audio]').trigger('click');
    expect(mocks.replace).toHaveBeenCalledWith({
      query: {
        audio_unit: '10',
        audio_parent: undefined,
        audio_file_q: 'SYNTHETIC copy outside old filter',
        audio_file_page: 1,
        audio_file_source: undefined,
        audio_file_format: undefined,
      },
    });
    await wrapper.setProps({
      context: { ...context, capabilities: { configure: false } },
    });
    await flushPromises();
    expect(wrapper.find('[data-audio-copy-receipt="45"]').exists()).toBe(false);
  });

  it('names source, format and page size independently of their option contents', async () => {
    const wrapper = fixture();
    await flushPromises();
    [
      ['[data-audio-file-source-filter]', 'SOURCE'],
      ['[data-audio-file-format-filter]', 'FORMAT'],
      ['[data-audio-file-size]', 'PAGE_SIZE'],
    ].forEach(([selector, label]) => {
      const control = wrapper.get(selector);
      const text = wrapper.get(`label[for="${control.attributes('id')}"]`);
      expect(text.text()).toBe(`JRC_CONTACT_CENTER.AUDIO_FILES.${label}`);
      expect(text.element.control).toBe(control.element);
      expect(text.find('option').exists()).toBe(false);
    });
  });

  it.each([
    ['user_upload', 'SOURCE_UPLOAD'],
    ['browser_capture', 'SOURCE_CAPTURE'],
    [undefined, 'UNKNOWN_SOURCE'],
  ])(
    'shows the actual latest-version origin %s in its row without inventing missing provenance',
    async (source, shown) => {
      const item = structuredClone(row);
      item.latest_version.source_kind = source;
      API.audioAssets.mockResolvedValueOnce({
        data: {
          items: [item],
          meta: { page: 1, pages: 1, total: 1 },
          max_upload_bytes: 1000,
        },
      });
      const wrapper = fixture();
      await flushPromises();
      const displayed = wrapper
        .get('[data-audio-asset="44"]')
        .get('[data-audio-file-source="44"]');
      expect(displayed.text()).toContain(
        `JRC_CONTACT_CENTER.AUDIO_FILES.${shown}`
      );
      expect(API.audioAsset).not.toHaveBeenCalled();
    }
  );

  it('applies source and format drafts through the native route while retaining unit and unrelated filters', async () => {
    mocks.route.query = { audio_unit: '10', unrelated: 'preserved' };
    const wrapper = fixture();
    await flushPromises();
    await wrapper
      .get('[data-audio-file-source-filter]')
      .setValue('browser_capture');
    await wrapper.get('[data-audio-file-format-filter]').setValue('audio/ogg');
    await wrapper.get('[data-audio-file-search]').setValue('SYNTHETIC');
    expect(API.audioAssets).toHaveBeenCalledOnce();
    await wrapper.get('form').trigger('submit');
    expect(mocks.replace).toHaveBeenCalledWith({
      query: {
        ...mocks.route.query,
        audio_file_q: 'SYNTHETIC',
        audio_file_page: 1,
        audio_file_source: 'browser_capture',
        audio_file_format: 'audio/ogg',
      },
    });
  });

  it('requests scoped server filtering before totals and pagination and clears every selected criterion', async () => {
    mocks.route.query = {
      audio_unit: '10',
      audio_file_source: 'browser_capture',
      audio_file_format: 'audio/ogg',
      audio_file_q: 'SYNTHETIC',
    };
    const wrapper = fixture();
    await flushPromises();
    expect(API.audioAssets).toHaveBeenCalledWith('1', {
      unit_id: '10',
      folder_id: '',
      q: 'SYNTHETIC',
      page: 1,
      per_page: 20,
      source_kind: 'browser_capture',
      content_type: 'audio/ogg',
    });
    await wrapper.get('nav').findAll('button')[1].trigger('click');
    expect(mocks.replace).toHaveBeenCalledWith({
      query: { ...mocks.route.query, audio_file_page: 2 },
    });
    await wrapper.get('form').findAll('button')[1].trigger('click');
    expect(mocks.replace).toHaveBeenLastCalledWith({
      query: {
        ...mocks.route.query,
        audio_file_q: undefined,
        audio_file_source: undefined,
        audio_file_format: undefined,
        audio_file_page: 1,
      },
    });
    expect(wrapper.get('[data-audio-file-source-filter]').element.value).toBe(
      ''
    );
    expect(wrapper.get('[data-audio-file-format-filter]').element.value).toBe(
      ''
    );
  });

  it('discards an earlier unfiltered response after the native source filter changes', async () => {
    let finish;
    API.audioAssets.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const wrapper = fixture();
    API.audioAssets.mockResolvedValueOnce({
      data: {
        items: [],
        meta: { page: 1, pages: 0, total: 0 },
        max_upload_bytes: 1000,
      },
    });
    mocks.route.query.audio_file_source = 'browser_capture';
    await flushPromises();
    finish({
      data: {
        items: [structuredClone(row)],
        meta: { page: 1, pages: 1, total: 1 },
        max_upload_bytes: 1000,
      },
    });
    await flushPromises();
    expect(wrapper.find('[data-audio-asset="44"]').exists()).toBe(false);
    expect(API.audioAssets).toHaveBeenLastCalledWith(
      '1',
      expect.objectContaining({ source_kind: 'browser_capture' })
    );
  });

  it('shows a native invalid-filter error without silently requesting or displaying an unfiltered fallback', async () => {
    mocks.route.query.audio_file_source = 'nico';
    API.audioAssets.mockRejectedValueOnce({
      response: {
        status: 422,
        data: { error: 'invalid_institutional_audio_filter' },
      },
    });
    const wrapper = fixture();
    await flushPromises();
    expect(wrapper.get('[role="alert"]').text()).toContain(
      'JRC_CONTACT_CENTER.AUDIO_FILES.ERROR'
    );
    expect(wrapper.find('[data-audio-asset="44"]').exists()).toBe(false);
    expect(API.audioAssets).toHaveBeenCalledOnce();
  });

  it('keeps common fields across source methods, blocks save while capturing and requires review before the existing native upload', async () => {
    const wrapper = fixture({ AudioCaptureDraft: true });
    await flushPromises();
    await wrapper.get('[data-new-audio-asset]').trigger('click');
    await flushPromises();
    await wrapper
      .get('[data-audio-asset-name]')
      .setValue('SYNTHETIC captured draft');
    await wrapper.get('[data-audio-source-capture]').trigger('click');
    await flushPromises();
    expect(wrapper.get('[data-audio-asset-name]').element.value).toBe(
      'SYNTHETIC captured draft'
    );
    expect(wrapper.find('[data-audio-asset-file]').exists()).toBe(false);
    const capture = wrapper.findComponent(AudioCaptureDraft);
    capture.vm.$emit('busy', true);
    await flushPromises();
    expect(wrapper.get('[data-submit]').element.disabled).toBe(true);
    capture.vm.$emit('busy', false);
    const file = new File(['SYNTHETIC'.padEnd(60, '0')], 'capture.ogg', {
      type: 'audio/ogg',
    });
    capture.vm.$emit('selected', file);
    await flushPromises();
    expect(wrapper.get('[data-audio-selected-file]').text()).toContain(
      'capture.ogg'
    );
    expect(wrapper.get('[data-submit]').element.disabled).toBe(true);
    await wrapper.get('[data-review-audio-asset]').setValue(true);
    API.receiveAudioAsset.mockResolvedValueOnce({
      data: {
        account_id: '1',
        item: structuredClone(row),
        received_version: {
          ...structuredClone(row.latest_version),
          source_kind: 'browser_capture',
        },
      },
    });
    await wrapper.get('[role="dialog"]').trigger('submit');
    await flushPromises();
    expect(API.receiveAudioAsset).toHaveBeenCalledOnce();
    const [account, body] = API.receiveAudioAsset.mock.calls[0];
    expect(account).toBe('1');
    expect(body.get('source_kind')).toBe('browser_capture');
    expect(body.get('file')).toBe(file);
    expect(body.get('asset[name]')).toBe('SYNTHETIC captured draft');
  });

  it.each([
    [1, '00:00.001'],
    [12000, '00:12'],
    [3600000, '1:00:00'],
  ])(
    'displays the actual verified %i millisecond duration without rounding a short file to zero',
    async (ms, shown) => {
      const item = structuredClone(row);
      item.latest_version.technical_verification = {
        ready: true,
        metadata: { duration_ms: ms },
      };
      API.audioAssets.mockResolvedValueOnce({
        data: {
          items: [item],
          meta: { page: 1, pages: 1, total: 1 },
          max_upload_bytes: 1000,
        },
      });
      const wrapper = fixture();
      await flushPromises();
      expect(wrapper.get('[data-audio-file-duration="44"]').text()).toBe(shown);
      expect(wrapper.get('[data-mobile-audio-file-duration="44"]').text()).toBe(
        shown
      );
    }
  );

  it('does not display a previous duration when the supplied current verification is unavailable', async () => {
    const item = structuredClone(row);
    item.latest_version.technical_verification = {
      ready: false,
      state: 'unavailable',
      metadata: { duration_ms: 12000 },
    };
    API.audioAssets.mockResolvedValueOnce({
      data: {
        items: [item],
        meta: { page: 1, pages: 1, total: 1 },
        max_upload_bytes: 1000,
      },
    });
    const wrapper = fixture();
    await flushPromises();
    expect(wrapper.get('[data-audio-file-duration="44"]').text()).toBe(
      'JRC_CONTACT_CENTER.AUDIO_FILES.DURATION_UNKNOWN'
    );
    expect(wrapper.text()).not.toContain('00:12');
    expect(wrapper.text()).not.toContain('00:00');
  });

  it('invalidates list and details while a current inspection is uncertain and updates only the matching exact-version receipt', async () => {
    const wrapper = fixture();
    await flushPromises();
    await wrapper.get('[data-audio-asset-details-open="44"]').trigger('click');
    await flushPromises();
    const history = wrapper.findComponent(AudioInspectionHistory);
    const source = {
      accountId: '1',
      unitId: '10',
      assetId: '44',
      versionId: '90',
    };
    const proof = {
      id: '99',
      audio_version_id: '90',
      unit_id: '10',
      expected_sha256: row.latest_version.sha256,
      state: 'clean',
      probe_state: 'valid',
      ready: true,
      metadata: { duration_ms: 12000 },
    };
    history.vm.$emit('latest', { ...source, proof });
    await flushPromises();
    expect(wrapper.get('[data-audio-file-duration="44"]').text()).toBe('00:12');
    expect(wrapper.get('[data-audio-details-duration]').text()).toBe('00:12');
    history.vm.$emit('latest', { ...source, proof: null });
    await flushPromises();
    expect(wrapper.get('[data-audio-file-duration="44"]').text()).toBe(
      'JRC_CONTACT_CENTER.AUDIO_FILES.DURATION_UNKNOWN'
    );
    expect(wrapper.get('[data-audio-details-duration]').text()).toBe(
      'JRC_CONTACT_CENTER.AUDIO_FILES.DURATION_UNKNOWN'
    );
    history.vm.$emit('latest', {
      ...source,
      proof: { ...proof, metadata: { duration_ms: 1 } },
    });
    await flushPromises();
    expect(wrapper.get('[data-audio-file-duration="44"]').text()).toBe(
      '00:00.001'
    );
    expect(wrapper.get('[data-audio-details-duration]').text()).toBe(
      '00:00.001'
    );
    expect(API.receiveAudioVersion).not.toHaveBeenCalled();
  });

  it.each([
    { accountId: '2', unitId: '10', assetId: '44', versionId: '90' },
    { accountId: '1', unitId: '11', assetId: '44', versionId: '90' },
    { accountId: '1', unitId: '10', assetId: '44', versionId: '91' },
  ])('ignores an observation event from another source: %o', async source => {
    const wrapper = fixture();
    await flushPromises();
    await wrapper.get('[data-audio-asset-details-open="44"]').trigger('click');
    await flushPromises();
    wrapper.findComponent(AudioInspectionHistory).vm.$emit('latest', {
      ...source,
      proof: {
        id: '99',
        audio_version_id: '90',
        unit_id: '10',
        expected_sha256: row.latest_version.sha256,
        ready: true,
        metadata: { duration_ms: 12000 },
      },
    });
    await flushPromises();
    expect(wrapper.get('[data-audio-file-duration="44"]').text()).toBe(
      'JRC_CONTACT_CENTER.AUDIO_FILES.DURATION_UNKNOWN'
    );
    expect(wrapper.text()).not.toContain('00:12');
  });

  it('opens current authorized details from the native endpoint and closes without mutating the file', async () => {
    const wrapper = fixture();
    await flushPromises();
    await wrapper.get('[data-audio-asset-details-open="44"]').trigger('click');
    await flushPromises();
    expect(API.audioAsset).toHaveBeenCalledWith('1', '44');
    const details = wrapper.get('[data-audio-asset-details]');
    expect(details.text()).toContain(row.name);
    expect(details.text()).toContain(row.latest_version.sha256);
    expect(details.text()).toContain('audio/wav');
    expect(details.find('audio, a[download]').exists()).toBe(false);
    await details.get('[data-close-audio-details]').trigger('click');
    expect(wrapper.find('[data-audio-asset-details]').exists()).toBe(false);
    expect(API.updateAudioAsset).not.toHaveBeenCalled();
    expect(API.receiveAudioVersion).not.toHaveBeenCalled();
  });

  it('ignores a slower previous selection instead of showing one file under another selection', async () => {
    const other = {
      ...row,
      id: '45',
      name: 'SYNTHETIC next selection',
      latest_version: null,
    };
    API.audioAssets.mockResolvedValueOnce({
      data: {
        items: [row, other],
        meta: { page: 1, pages: 1, total: 2 },
        max_upload_bytes: 1000,
      },
    });
    let resolvePrevious;
    API.audioAsset.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolvePrevious = resolve;
        })
    );
    API.audioAsset.mockResolvedValueOnce({
      data: { account_id: '1', item: other },
    });
    const wrapper = fixture();
    await flushPromises();
    await wrapper.get('[data-audio-asset-details-open="44"]').trigger('click');
    await wrapper.get('[data-audio-asset-details-open="45"]').trigger('click');
    await flushPromises();
    expect(wrapper.get('[data-audio-asset-details]').text()).toContain(
      other.name
    );
    resolvePrevious({ data: { account_id: '1', item: row } });
    await flushPromises();
    expect(wrapper.get('[data-audio-asset-details]').text()).toContain(
      other.name
    );
    expect(wrapper.get('[data-audio-asset-details]').text()).not.toContain(
      row.name
    );
  });

  it('forgets an outstanding details request after a native unit change', async () => {
    let resolve;
    API.audioAsset.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const wrapper = fixture();
    await flushPromises();
    await wrapper.get('[data-audio-asset-details-open="44"]').trigger('click');
    API.audioAssets.mockResolvedValueOnce({
      data: {
        items: [],
        meta: { page: 1, pages: 0, total: 0 },
        max_upload_bytes: 1000,
      },
    });
    await wrapper.setProps({ unitId: '11' });
    resolve({ data: { account_id: '1', item: row } });
    await flushPromises();
    expect(wrapper.find('[data-audio-asset-details]').exists()).toBe(false);
  });

  it('withholds details and clears private rows when current server authority is denied', async () => {
    API.audioAsset.mockRejectedValueOnce({ response: { status: 403 } });
    const wrapper = fixture();
    await flushPromises();
    await wrapper.get('[data-audio-asset-details-open="44"]').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-audio-asset-details]').exists()).toBe(false);
    expect(wrapper.find('[data-audio-asset="44"]').exists()).toBe(false);
    expect(wrapper.emitted('denied')).toHaveLength(1);
  });

  it('does not display details returned for another account or unit', async () => {
    API.audioAsset.mockResolvedValueOnce({
      data: { account_id: '2', item: { ...row, unit_id: '11' } },
    });
    const wrapper = fixture();
    await flushPromises();
    await wrapper.get('[data-audio-asset-details-open="44"]').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-audio-asset-details]').exists()).toBe(false);
    expect(wrapper.find('[role="alert"]').text()).toContain(
      'JRC_CONTACT_CENTER.AUDIO_FILES.ERROR'
    );
  });

  it('returns to the last real page after a move removes the final row without discarding folder or search context', async () => {
    mocks.route.query = {
      audio_file_page: '2',
      audio_file_q: 'SYNTHETIC',
      audio_parent: '88',
    };
    API.audioAssets.mockResolvedValueOnce({
      data: {
        items: [],
        meta: { page: 2, pages: 1, total: 5 },
        max_upload_bytes: 1000,
      },
    });
    fixture();
    await flushPromises();
    expect(mocks.replace).toHaveBeenCalledWith({
      query: { ...mocks.route.query, audio_file_page: 1 },
    });
    expect(API.audioAssets).toHaveBeenCalledOnce();
  });
  it('renders explicit quarantine and actual file metadata without a preview, download, publication or invented duration', async () => {
    const wrapper = fixture();
    await flushPromises();
    expect(API.audioAssets).toHaveBeenCalledWith('1', {
      unit_id: '10',
      folder_id: '',
      q: '',
      page: 1,
      per_page: 20,
    });
    expect(wrapper.text()).toContain(row.name);
    expect(wrapper.text()).toContain('JRC_CONTACT_CENTER.AUDIO_FILES.PRIVATE');
    expect(wrapper.findAll('audio, video, a[download]')).toHaveLength(0);
    expect(wrapper.text()).not.toContain('00:00');
    expect(wrapper.text()).toContain('SYNTHETIC.wav');
  });

  it('preserves the other native route filters while paginating and clearing the current file query', async () => {
    mocks.route.query = {
      audio_unit: '10',
      audio_parent: '88',
      audio_file_q: 'SYNTHETIC',
      unrelated: 'preserved',
    };
    const wrapper = fixture();
    await flushPromises();
    const nav = wrapper.get('nav');
    await nav.findAll('button')[1].trigger('click');
    expect(mocks.replace).toHaveBeenCalledWith({
      query: { ...mocks.route.query, audio_file_page: 2 },
    });
    await wrapper.get('form').findAll('button')[1].trigger('click');
    expect(mocks.replace).toHaveBeenLastCalledWith({
      query: {
        ...mocks.route.query,
        audio_file_page: 1,
        audio_file_q: undefined,
      },
    });
  });

  it('opens an authorized record afresh and persists a reviewed metadata edit using native CAS', async () => {
    const wrapper = fixture();
    await flushPromises();
    await wrapper.get('[data-edit-audio-asset="44"]').trigger('click');
    await flushPromises();
    await wrapper.get('[data-audio-asset-name]').setValue('SYNTHETIC renamed');
    await wrapper.get('[data-review-audio-asset]').setValue(true);
    await wrapper.get('[role="dialog"]').trigger('submit');
    await flushPromises();
    expect(API.audioAsset).toHaveBeenCalledWith('1', '44');
    expect(API.updateAudioAsset).toHaveBeenCalledWith(
      '1',
      '44',
      expect.objectContaining({ name: 'SYNTHETIC renamed' }),
      { expected_revision: row.revision }
    );
    expect(API.receiveAudioAsset).not.toHaveBeenCalled();
    expect(wrapper.find('[data-audio-asset-editor]').exists()).toBe(false);
  });

  it('loads actual scoped immutable history and forgets every private item when history access is denied', async () => {
    const wrapper = fixture();
    await flushPromises();
    await wrapper.get('[data-audio-asset-history="44"]').trigger('click');
    await flushPromises();
    expect(API.audioVersions).toHaveBeenCalledWith('1', '44', {
      page: 1,
      per_page: 10,
    });
    expect(wrapper.get('[data-audio-version="2"]').text()).toContain(
      'f'.repeat(64)
    );
    API.audioVersions.mockRejectedValueOnce({ response: { status: 403 } });
    await wrapper.get('[data-audio-asset-history="44"]').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-audio-version-history]').exists()).toBe(false);
    expect(wrapper.text()).not.toContain(row.name);
    expect(wrapper.find('[data-audio-asset-editor]').exists()).toBe(false);
  });

  it('discards a delayed list belonging to an old native unit', async () => {
    let resolve;
    API.audioAssets.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const wrapper = fixture();
    await wrapper.setProps({ unitId: '11' });
    await flushPromises();
    resolve({
      data: {
        items: [{ ...row, name: 'SYNTHETIC stale private item' }],
        meta: { total: 1, pages: 1 },
        max_upload_bytes: 1000,
      },
    });
    await flushPromises();
    expect(wrapper.text()).not.toContain('SYNTHETIC stale private item');
    expect(API.audioAssets).toHaveBeenLastCalledWith(
      '1',
      expect.objectContaining({ unit_id: '11' })
    );
  });

  it('closes a private draft after a profile change and does not infer configuration permission from a recording role', async () => {
    const wrapper = fixture();
    await flushPromises();
    await wrapper.get('[data-edit-audio-asset="44"]').trigger('click');
    await flushPromises();
    API.audioAssets.mockRejectedValueOnce({ response: { status: 401 } });
    mocks.user.value.accounts[0].permissions = [
      'jrc_contact_center_recordings_listen',
    ];
    await wrapper.setProps({
      context: { ...context, capabilities: { configure: false } },
    });
    await flushPromises();
    expect(wrapper.find('[data-audio-asset-editor]').exists()).toBe(false);
    expect(wrapper.find('[data-new-audio-asset]').exists()).toBe(false);
    expect(wrapper.text()).not.toContain(row.name);
    expect(API.updateAudioAsset).not.toHaveBeenCalled();
  });
});
