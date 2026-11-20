import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { computed, defineComponent, reactive, ref } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import AudioFolderLibrary from './AudioFolderLibrary.vue';

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
    audioFolders: vi.fn(),
    audioFolder: vi.fn(),
    saveAudioFolder: vi.fn(),
    configurationRecord: vi.fn(),
  },
}));
const Dialog = defineComponent({
  props: { disableConfirmButton: Boolean },
  emits: ['confirm'],
  setup(props, { expose, emit }) {
    const visible = ref(false);
    expose({
      open: () => {
        visible.value = true;
      },
      close: () => {
        visible.value = false;
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
const context = {
  capabilities: { configure: true },
  units: [{ id: '10', name: 'SYNTHETIC native unit' }],
};
const record = (values = {}) => ({
  id: '9',
  unit_id: '10',
  parent_id: null,
  parent_name: null,
  name: 'SYNTHETIC root',
  description: '',
  revision: 'a'.repeat(64),
  ...values,
});
const setup = () =>
  mount(AudioFolderLibrary, {
    props: { accountId: '1', context },
    global: { stubs: { Dialog } },
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
  API.audioFolders.mockResolvedValue({
    data: { items: [record()], meta: { page: 1, pages: 2, total: 21 } },
  });
  API.audioFolder.mockResolvedValue({ data: { item: record() } });
  API.configurationRecord.mockResolvedValue({
    data: { item: record({ revision: 'b'.repeat(64) }) },
  });
  API.saveAudioFolder.mockResolvedValue({ data: { item: record() } });
});

describe('unit scoped institutional folder UI', () => {
  it('loads native unit filters and preserves query pagination without requesting another account', async () => {
    const wrapper = setup();
    await flushPromises();
    expect(API.audioFolders).toHaveBeenCalledWith('1', {
      unit_id: '10',
      parent_id: '',
      q: '',
      page: 1,
      per_page: 20,
    });
    await wrapper.get('[data-audio-search]').setValue('SYNTHETIC search');
    await wrapper.find('form').trigger('submit');
    expect(mocks.replace).toHaveBeenCalledWith({
      query: { audio_q: 'SYNTHETIC search', audio_page: 1 },
    });
    expect(wrapper.find('[data-audio-folder="9"]').exists()).toBe(true);
    expect(wrapper.get('[data-audio-library-limits]').attributes('role')).toBe(
      'status'
    );
    expect(wrapper.get('[data-audio-library-limits]').text()).toBe(
      'JRC_CONTACT_CENTER.AUDIO_FOLDERS.LIMITS'
    );
  });

  it('requires explicit review and persists a folder rather than an audio or provider command', async () => {
    const wrapper = setup();
    await flushPromises();
    await wrapper.get('[data-new-audio-folder]').trigger('click');
    await flushPromises();
    await wrapper.get('[data-audio-folder-name]').setValue('SYNTHETIC new');
    expect(wrapper.get('[data-submit]').element.disabled).toBe(true);
    await wrapper.get('[data-review-audio-folder]').setValue(true);
    await wrapper.get('[data-submit]').trigger('submit');
    await flushPromises();
    expect(API.saveAudioFolder).toHaveBeenCalledTimes(1);
    expect(API.saveAudioFolder.mock.calls[0].slice(0, 3)).toEqual([
      '1',
      undefined,
      {
        name: 'SYNTHETIC new',
        description: '',
        parent_id: null,
        unit_id: '10',
      },
    ]);
    expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
  });

  it('does not discard a private draft when observed counters refresh without authority changes', async () => {
    const wrapper = setup();
    await flushPromises();
    await wrapper.get('[data-new-audio-folder]').trigger('click');
    await flushPromises();
    await wrapper.get('[data-audio-folder-name]').setValue('SYNTHETIC kept');
    await wrapper.setProps({
      context: { ...context, observed_at: 'SYNTHETIC later', cards: [] },
    });
    await flushPromises();
    expect(wrapper.get('[data-audio-folder-name]').element.value).toBe(
      'SYNTHETIC kept'
    );
  });

  it('closes and clears the private editor after a profile or user change', async () => {
    const wrapper = setup();
    await flushPromises();
    await wrapper.get('[data-new-audio-folder]').trigger('click');
    await flushPromises();
    await wrapper
      .get('[data-audio-folder-name]')
      .setValue('SYNTHETIC old user draft');
    mocks.user.value = {
      id: 8,
      accounts: [{ id: 1, role: 'administrator', permissions: [] }],
    };
    await flushPromises();
    expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
    await wrapper.get('[data-new-audio-folder]').trigger('click');
    await flushPromises();
    expect(wrapper.get('[data-audio-folder-name]').element.value).toBe('');
  });

  it('preserves the failed draft and never automatically retries an uncertain write', async () => {
    API.saveAudioFolder.mockRejectedValueOnce({
      response: { status: 503, data: { error: 'synthetic_unavailable' } },
    });
    const wrapper = setup();
    await flushPromises();
    await wrapper.get('[data-new-audio-folder]').trigger('click');
    await flushPromises();
    await wrapper.get('[data-audio-folder-name]').setValue('SYNTHETIC retry');
    await wrapper.get('[data-review-audio-folder]').setValue(true);
    await wrapper.get('[data-submit]').trigger('submit');
    await flushPromises();
    expect(wrapper.get('[data-audio-folder-name]').element.value).toBe(
      'SYNTHETIC retry'
    );
    expect(wrapper.get('[data-submit]').element.disabled).toBe(true);
    expect(API.saveAudioFolder).toHaveBeenCalledTimes(1);
    expect(wrapper.find('[role="alert"]').exists()).toBe(true);
  });

  it('retains the native revision conflict instead of overwriting a renamed or moved folder', async () => {
    API.saveAudioFolder.mockRejectedValueOnce({
      response: {
        status: 409,
        data: { error: 'stale_configuration_revision' },
      },
    });
    const wrapper = setup();
    await flushPromises();
    await wrapper.get('[data-edit-audio-folder="9"]').trigger('click');
    await flushPromises();
    await wrapper
      .get('[data-audio-folder-name]')
      .setValue('SYNTHETIC conflicting draft');
    await wrapper.get('[data-review-audio-folder]').setValue(true);
    await wrapper.get('[data-submit]').trigger('submit');
    await flushPromises();
    expect(wrapper.find('[data-configuration-conflict]').exists()).toBe(true);
    expect(wrapper.get('[data-audio-folder-name]').element.value).toBe(
      'SYNTHETIC conflicting draft'
    );
    expect(wrapper.get('[data-submit]').element.disabled).toBe(true);
    expect(API.saveAudioFolder.mock.calls[0][3]).toEqual({
      expected_revision: 'a'.repeat(64),
    });
  });

  it('does not request records for a unit absent from the current native coverage', async () => {
    mocks.route.query.audio_unit = '999';
    const wrapper = setup();
    await flushPromises();
    expect(API.audioFolders).not.toHaveBeenCalled();
    expect(wrapper.get('[data-new-audio-folder]').element.disabled).toBe(true);
  });

  it('ignores an old response after switching account and operational unit', async () => {
    let finish;
    API.audioFolders.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const wrapper = setup();
    await flushPromises();
    await wrapper.setProps({
      accountId: '2',
      context: {
        capabilities: { configure: true },
        units: [{ id: '20', name: 'SYNTHETIC new unit' }],
      },
    });
    await flushPromises();
    finish({
      data: {
        items: [record({ id: '77', name: 'SYNTHETIC old account' })],
        meta: { page: 1, pages: 1, total: 1 },
      },
    });
    await flushPromises();
    expect(wrapper.text()).not.toContain('SYNTHETIC old account');
    expect(API.audioFolders).toHaveBeenCalledWith(
      '2',
      expect.objectContaining({ unit_id: '20' })
    );
  });
});
