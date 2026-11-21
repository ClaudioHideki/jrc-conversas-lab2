import { afterEach, describe, expect, it, vi } from 'vitest';
import { flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import IvrAudioReferencePicker from './IvrAudioReferencePicker.vue';

vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: {
    audioAssets: vi.fn(),
    audioVersions: vi.fn(),
    audioVersion: vi.fn(),
  },
}));
const reference = { asset_id: '11', version_id: '21', sha256: 'a'.repeat(64) };
const version = {
  id: '21',
  audio_asset_id: '11',
  unit_id: '7',
  number: 1,
  sha256: reference.sha256,
  file_name: 'Synthetic.wav',
  ready: false,
  technical_verification: { id: '31', audio_version_id: '21', ready: true },
};
const wrappers = [];
const setup = (props = {}) => {
  const wrapper = mount(IvrAudioReferencePicker, {
    props: { accountId: '1', unitId: '7', ...props },
    global: { stubs: { AudioVersionPreview: true } },
  });
  wrappers.push(wrapper);
  return wrapper;
};
afterEach(() => {
  wrappers.splice(0).forEach(wrapper => wrapper.unmount());
  vi.resetAllMocks();
});

describe('existing IVR menu institutional audio controls', () => {
  it('gives every menu its own explicit label/control association', async () => {
    API.audioAssets.mockResolvedValue({
      data: { items: [], meta: { page: 1, pages: 0 } },
    });
    const first = setup();
    const second = setup();
    await first.get('[data-ivr-audio-choose]').trigger('click');
    await second.get('[data-ivr-audio-choose]').trigger('click');
    await flushPromises();
    const left = first.get('[data-ivr-audio-asset]');
    const right = second.get('[data-ivr-audio-asset]');
    expect(left.attributes('id')).not.toBe(right.attributes('id'));
    expect(
      first.get(`label[for="${left.attributes('id')}"]`).element.control
    ).toBe(left.element);
    expect(
      second.get(`label[for="${right.attributes('id')}"]`).element.control
    ).toBe(right.element);
  });
  it('requires explicit asset, exact version and confirmation without auto-selecting or publishing', async () => {
    API.audioAssets.mockResolvedValue({
      data: {
        items: [{ id: '11', unit_id: '7', name: 'Synthetic menu audio' }],
        meta: { page: 1, pages: 1 },
      },
    });
    API.audioVersions.mockResolvedValue({
      data: { items: [version], meta: { page: 1, pages: 1 } },
    });
    const wrapper = setup();
    expect(wrapper.text()).toContain('Não publica a URA');
    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
    await wrapper.get('[data-ivr-audio-choose]').trigger('click');
    await flushPromises();
    const assetSelect = wrapper.get('[data-ivr-audio-asset]');
    const assetLabel = wrapper.get(
      `label[for="${assetSelect.attributes('id')}"]`
    );
    expect(assetLabel.text()).toBe('Áudio institucional');
    expect(assetLabel.element.control).toBe(assetSelect.element);
    expect(assetLabel.find('option').exists()).toBe(false);
    await wrapper.get('[data-ivr-audio-asset]').setValue('11');
    await flushPromises();
    const versionSelect = wrapper.get('[data-ivr-audio-version]');
    const versionLabel = wrapper.get(
      `label[for="${versionSelect.attributes('id')}"]`
    );
    expect(versionLabel.text()).toBe('Versão do áudio');
    expect(versionLabel.element.control).toBe(versionSelect.element);
    expect(versionLabel.find('option').exists()).toBe(false);
    expect(
      wrapper.get('[data-ivr-audio-confirm]').attributes('disabled')
    ).toBeDefined();
    await wrapper.get('[data-ivr-audio-version]').setValue('21');
    expect(
      wrapper.findComponent({ name: 'AudioVersionPreview' }).exists()
    ).toBe(true);
    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
    await wrapper.get('[data-ivr-audio-confirm]').trigger('click');
    expect(wrapper.emitted('update:modelValue')).toEqual([[reference]]);
  });
  it('shows the exact saved version and removes only its draft reference with explicit action', async () => {
    API.audioVersion.mockResolvedValue({ data: { item: version } });
    const wrapper = setup({ modelValue: reference });
    await flushPromises();
    expect(wrapper.get('[data-ivr-audio-pinned]').text()).toContain(
      'Versão 1 fixada'
    );
    await wrapper.get('[data-ivr-audio-remove]').trigger('click');
    expect(wrapper.emitted('update:modelValue')).toEqual([[null]]);
    expect(API.audioAssets).not.toHaveBeenCalled();
  });
  it('preserves an unavailable stored pin until the user removes or replaces it', async () => {
    API.audioVersion.mockRejectedValue({ response: { status: 404 } });
    const wrapper = setup({ modelValue: reference });
    await flushPromises();
    expect(wrapper.get('[role="alert"]').text()).toContain(
      'O vínculo salvo não está disponível'
    );
    expect(wrapper.find('[data-ivr-audio-pinned]').exists()).toBe(false);
    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
    expect(wrapper.get('[data-ivr-audio-remove]').exists()).toBe(true);
  });
  it('keeps disabled controls read-only and never treats a readiness badge as PABX publication', async () => {
    API.audioVersion.mockResolvedValue({ data: { item: version } });
    const wrapper = setup({ modelValue: reference, disabled: true });
    await flushPromises();
    await wrapper.get('[data-ivr-audio-choose]').trigger('click');
    await wrapper.get('[data-ivr-audio-remove]').trigger('click');
    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
    expect(API.audioAssets).not.toHaveBeenCalled();
    expect(wrapper.text()).toContain('Não publica a URA');
  });
});
