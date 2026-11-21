import { afterEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import AudioIvrUsages from './AudioIvrUsages.vue';

vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { audioUsages: vi.fn() },
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
const Dialog = defineComponent({
  emits: ['close'],
  setup(_, { expose, emit }) {
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
      close: () => {
        visible.value = false;
        emit('close');
      },
    };
  },
  template:
    '<div v-if="visible" role="dialog"><slot /><button data-close @click="close"></button></div>',
});
const payload = (page = 1) => ({
  account_id: '1',
  audio_asset_id: '11',
  unit_id: '7',
  coverage: 'current_local_ivr_drafts_only',
  provider_configuration_verified: false,
  items: [
    {
      draft_id: String(page + 40),
      draft_revision: 3,
      name: 'SYNTHETIC draft',
      status: 'draft',
      unit_id: '7',
      references: [
        { node_id: 'entry', audio_version_id: '21', sha256: 'a'.repeat(64) },
      ],
      local_only: true,
      provider_applied: false,
    },
  ],
  meta: { page, total: 11, per_page: 10, pages: 2 },
});
const wrappers = [];
const setup = (props = {}) => {
  const wrapper = mount(AudioIvrUsages, {
    props: {
      accountId: '1',
      assetId: '11',
      unitId: '7',
      canManage: true,
      ...props,
    },
    global: { stubs: { Dialog } },
  });
  wrappers.push(wrapper);
  return wrapper;
};
afterEach(() => {
  wrappers.splice(0).forEach(wrapper => wrapper.unmount());
  vi.resetAllMocks();
});
const open = async wrapper => {
  await wrapper.get('[data-audio-usages-open]').trigger('click');
  await flushPromises();
};

describe('authorized current local IVR audio references', () => {
  it('loads only after explicit action and identifies limited local coverage without provider claims', async () => {
    API.audioUsages.mockResolvedValue({ data: payload() });
    const wrapper = setup();
    expect(API.audioUsages).not.toHaveBeenCalled();
    await open(wrapper);
    expect(API.audioUsages).toHaveBeenCalledTimes(1);
    expect(API.audioUsages).toHaveBeenCalledWith('1', '11', {
      page: 1,
      per_page: 10,
    });
    expect(wrapper.get('[data-audio-usages]').text()).toContain(
      'AUDIO_USAGES.LIMITS'
    );
    expect(wrapper.get('[data-audio-usage-draft="41"]').text()).toContain('21');
    expect(wrapper.text()).toContain('a'.repeat(64));
    expect(wrapper.find('audio').exists()).toBe(false);
  });
  it('does not request anything without current configure access', async () => {
    const wrapper = setup({ canManage: false });
    await open(wrapper);
    expect(API.audioUsages).not.toHaveBeenCalled();
    expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
  });
  it('paginates with the same authorized asset and replaces previous rows', async () => {
    API.audioUsages
      .mockResolvedValueOnce({ data: payload() })
      .mockResolvedValueOnce({ data: payload(2) });
    const wrapper = setup();
    await open(wrapper);
    await wrapper.get('nav button:last-child').trigger('click');
    await flushPromises();
    expect(API.audioUsages).toHaveBeenLastCalledWith('1', '11', {
      page: 2,
      per_page: 10,
    });
    expect(wrapper.find('[data-audio-usage-draft="41"]').exists()).toBe(false);
    expect(wrapper.find('[data-audio-usage-draft="42"]').exists()).toBe(true);
  });
  it('shows a scoped empty result without claiming absence of provider usages', async () => {
    const data = payload();
    data.items = [];
    data.meta = { page: 1, total: 0, pages: 0, per_page: 10 };
    API.audioUsages.mockResolvedValue({ data });
    const wrapper = setup();
    await open(wrapper);
    expect(wrapper.text()).toContain('AUDIO_USAGES.EMPTY');
    expect(wrapper.text()).toContain('AUDIO_USAGES.LIMITS');
    expect(wrapper.find('nav').exists()).toBe(false);
  });
  it('distinguishes archived local heads from current drafts', async () => {
    const data = payload();
    data.items[0].status = 'archived';
    API.audioUsages.mockResolvedValue({ data });
    const wrapper = setup();
    await open(wrapper);
    expect(wrapper.get('[data-audio-usage-draft]').text()).toContain(
      'AUDIO_USAGES.ARCHIVED'
    );
    expect(wrapper.get('[data-audio-usage-draft]').text()).not.toContain(
      'AUDIO_USAGES.LOCAL'
    );
  });
  it('shows a recoverable error without retaining earlier rows or assuming an empty successful result', async () => {
    API.audioUsages
      .mockRejectedValueOnce(new Error('SYNTHETIC unavailable'))
      .mockResolvedValueOnce({ data: payload() });
    const wrapper = setup();
    await open(wrapper);
    expect(wrapper.get('[role="alert"]').text()).toContain(
      'AUDIO_USAGES.ERROR'
    );
    expect(wrapper.text()).not.toContain('AUDIO_USAGES.EMPTY');
    await wrapper.get('[data-audio-usages-retry]').trigger('click');
    await flushPromises();
    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
    expect(wrapper.find('[data-audio-usage-draft="41"]').exists()).toBe(true);
  });
  it.each([401, 403, 404])(
    'forgets and closes denied data on native status%s',
    async status => {
      API.audioUsages.mockRejectedValue({ response: { status } });
      const wrapper = setup();
      await open(wrapper);
      expect(wrapper.emitted('denied')).toHaveLength(1);
      expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
      expect(wrapper.find('[data-audio-usage-draft]').exists()).toBe(false);
    }
  );
  it.each([
    'account_id',
    'audio_asset_id',
    'unit_id',
    'coverage',
    'provider_configuration_verified',
  ])(
    'rejects a mismatching response %s without showing its rows',
    async field => {
      const data = payload();
      data[field] =
        field === 'provider_configuration_verified'
          ? true
          : 'SYNTHETIC foreign';
      API.audioUsages.mockResolvedValue({ data });
      const wrapper = setup();
      await open(wrapper);
      expect(wrapper.find('[role="alert"]').exists()).toBe(true);
      expect(wrapper.find('[data-audio-usage-draft]').exists()).toBe(false);
    }
  );
  it.each([
    { accountId: '2' },
    { assetId: '12' },
    { unitId: '8' },
    { canManage: false },
  ])(
    'forgets late response data when the authorized context changes%s',
    async change => {
      let resolve;
      API.audioUsages.mockImplementation(
        () =>
          new Promise(done => {
            resolve = done;
          })
      );
      const wrapper = setup();
      await wrapper.get('[data-audio-usages-open]').trigger('click');
      await wrapper.setProps(change);
      resolve({ data: payload() });
      await flushPromises();
      expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
      expect(wrapper.find('[data-audio-usage-draft]').exists()).toBe(false);
    }
  );
  it('ignores a late result after the user closes the popup', async () => {
    let resolve;
    API.audioUsages.mockImplementation(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const wrapper = setup();
    await wrapper.get('[data-audio-usages-open]').trigger('click');
    await wrapper.get('[data-close]').trigger('click');
    resolve({ data: payload() });
    await flushPromises();
    expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
    expect(wrapper.find('[data-audio-usage-draft]').exists()).toBe(false);
  });
});
