import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, ref } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import AudioLibraryPreview from './AudioLibraryPreview.vue';
import AudioVersionPreview from './AudioVersionPreview.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { audioAsset: vi.fn() },
}));
const Dialog = defineComponent({
  emits: ['close'],
  setup(_, { expose, emit }) {
    const visible = ref(false);
    expose({
      open: () => {
        visible.value = true;
      },
      close: () => emit('close'),
    });
    return { visible };
  },
  template: '<section v-if="visible" role="dialog"><slot /></section>',
});
const asset = {
  id: '44',
  unit_id: '10',
  name: 'SYNTHETIC row preview',
  latest_version: {
    id: '90',
    audio_asset_id: '44',
    unit_id: '10',
    sha256: 'a'.repeat(64),
    technical_verification: {
      id: '12',
      ready: true,
      metadata: { duration_ms: 2000 },
    },
  },
};
const create = (props = {}) =>
  mount(AudioLibraryPreview, {
    props: { accountId: '1', unitId: '10', asset, canManage: true, ...props },
    global: { stubs: { Dialog, AudioVersionPreview: true } },
  });
enableAutoUnmount(afterEach);
beforeEach(() => {
  vi.clearAllMocks();
  API.audioAsset.mockResolvedValue({
    data: { account_id: '1', item: structuredClone(asset) },
  });
});

// Interaction boundaries only. The native Chrome case proves actual authorized bytes and media.
describe('direct institutional audio row preview', () => {
  it('reloads the selected native asset and opens only its exact currently verified version through the existing player', async () => {
    const wrapper = create();
    await flushPromises();
    expect(API.audioAsset).toHaveBeenCalledOnce();
    expect(API.audioAsset).toHaveBeenCalledWith('1', '44');
    expect(wrapper.getComponent(AudioVersionPreview).props()).toMatchObject({
      accountId: '1',
      assetId: '44',
      version: asset.latest_version,
      inspectionId: '12',
      canManage: true,
      openOnMount: true,
    });
    expect(wrapper.findAll('audio, a[download]')).toHaveLength(0);
  });

  it('does not silently switch the reviewed row to a new version', async () => {
    const item = structuredClone(asset);
    item.latest_version.id = '91';
    API.audioAsset.mockResolvedValue({ data: { account_id: '1', item } });
    const wrapper = create();
    await flushPromises();
    expect(wrapper.findComponent(AudioVersionPreview).exists()).toBe(false);
    expect(wrapper.get('[role="alert"]').text()).toContain('VERSION_CHANGED');
  });

  it('keeps an obsolete inspection from opening bytes even when the list previously showed readiness', async () => {
    const item = structuredClone(asset);
    item.latest_version.technical_verification.ready = false;
    API.audioAsset.mockResolvedValue({ data: { account_id: '1', item } });
    const wrapper = create();
    await flushPromises();
    expect(wrapper.findComponent(AudioVersionPreview).exists()).toBe(false);
    expect(wrapper.get('[role="alert"]').text()).toContain('NOT_READY');
  });

  it.each([401, 403, 404])(
    'withdraws the preview after native authorization returns %s',
    async status => {
      API.audioAsset.mockRejectedValue({ response: { status } });
      const wrapper = create();
      await flushPromises();
      expect(wrapper.emitted('denied')).toHaveLength(1);
      expect(wrapper.findComponent(AudioVersionPreview).exists()).toBe(false);
    }
  );

  it.each(['account', 'unit'])(
    'rejects a mismatched %s identity before mounting any media consumer',
    async scope => {
      const data = { account_id: '1', item: structuredClone(asset) };
      if (scope === 'account') data.account_id = '2';
      else data.item.unit_id = '11';
      API.audioAsset.mockResolvedValue({ data });
      const wrapper = create();
      await flushPromises();
      expect(wrapper.findComponent(AudioVersionPreview).exists()).toBe(false);
      expect(wrapper.get('[role="alert"]').text()).toContain('ERROR');
    }
  );

  it('discards a late response after the scoped preview has unmounted', async () => {
    let finish;
    API.audioAsset.mockImplementation(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const wrapper = create();
    wrapper.unmount();
    finish({ data: { account_id: '1', item: structuredClone(asset) } });
    await flushPromises();
    expect(wrapper.emitted('denied')).toBeUndefined();
  });

  it('does not fetch a private record without the current native configuration capability', async () => {
    const wrapper = create({ canManage: false });
    await flushPromises();
    expect(API.audioAsset).not.toHaveBeenCalled();
    expect(wrapper.emitted('denied')).toHaveLength(1);
    expect(wrapper.findComponent(AudioVersionPreview).exists()).toBe(false);
  });
});
