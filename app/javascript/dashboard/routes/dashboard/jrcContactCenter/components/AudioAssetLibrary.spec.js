import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { computed, defineComponent, reactive, ref } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import AudioAssetLibrary from './AudioAssetLibrary.vue';

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
    number: 2,
    file_name: 'SYNTHETIC.wav',
    byte_size: 60,
    ready: false,
    security_state: 'not_verified',
  },
};
const context = {
  capabilities: { configure: true },
  units: [{ id: '10' }, { id: '11' }],
};
const fixture = () =>
  mount(AudioAssetLibrary, {
    props: { accountId: '1', unitId: '10', folderId: '', context },
    global: { stubs: { Dialog, AudioFolderPicker: true } },
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
      items: [row],
      meta: { page: 1, pages: 2, total: 21 },
      max_upload_bytes: 1000,
    },
  });
  API.audioAsset.mockResolvedValue({ data: { item: row } });
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
    expect(wrapper.text()).toContain(
      'JRC_CONTACT_CENTER.AUDIO_FILES.NOT_VERIFIED'
    );
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
