import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import AcwPolicyEditor from './AcwPolicyEditor.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { acwPolicy: vi.fn(), updateAcwPolicy: vi.fn() },
}));
enableAutoUnmount(afterEach);
beforeEach(() => {
  vi.clearAllMocks();
  API.acwPolicy.mockResolvedValue({
    data: {
      item: { limits: { voice: 180, whatsapp: 180 }, voice_required: true },
    },
  });
  API.updateAcwPolicy.mockResolvedValue({
    data: {
      item: { limits: { voice: 180, whatsapp: 180 }, voice_required: false },
    },
  });
});
describe('company voice tabulation policy', () => {
  it('persists optional voice tabulation without changing WhatsApp limits', async () => {
    const wrapper = mount(AcwPolicyEditor, { props: { accountId: 1 } });
    await flushPromises();
    await wrapper.get('[data-voice-tabulation-required]').setValue(false);
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(API.updateAcwPolicy).toHaveBeenCalledWith(
      1,
      { voice: 180, whatsapp: 180 },
      { voice_required: false }
    );
    expect(
      wrapper.get('[data-voice-tabulation-required]').element.checked
    ).toBe(false);
  });
  it('keeps older APIs usable without inventing a supported policy setting', async () => {
    API.acwPolicy.mockResolvedValueOnce({
      data: { item: { limits: { voice: 180, whatsapp: 180 } } },
    });
    const wrapper = mount(AcwPolicyEditor, { props: { accountId: 1 } });
    await flushPromises();
    expect(wrapper.find('[data-voice-tabulation-required]').exists()).toBe(
      false
    );
    await wrapper.get('form').trigger('submit');
    expect(API.updateAcwPolicy).toHaveBeenCalledWith(
      1,
      { voice: 180, whatsapp: 180 },
      {}
    );
  });
});

describe('global ACW revision', () => {
  const item = (revision, voice = 180) => ({
    id: '1',
    revision,
    limits: { voice, whatsapp: 180 },
    voice_required: false,
  });
  it('sends the loaded revision and keeps the exact draft until explicit review after a conflict', async () => {
    API.acwPolicy.mockResolvedValueOnce({
      data: { item: item('a'.repeat(64)) },
    });
    API.acwPolicy.mockResolvedValueOnce({
      data: { item: item('b'.repeat(64), 300) },
    });
    API.updateAcwPolicy.mockRejectedValueOnce({
      response: { data: { error: 'stale_configuration_revision' } },
    });
    const wrapper = mount(AcwPolicyEditor, { props: { accountId: 1 } });
    await flushPromises();
    await wrapper.findAll('input[type="number"]')[0].setValue(240);
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(API.updateAcwPolicy).toHaveBeenCalledWith(
      1,
      { voice: 240, whatsapp: 180 },
      { voice_required: false, expected_revision: 'a'.repeat(64) }
    );
    expect(wrapper.get('[data-save-acw-policy]').element.disabled).toBe(true);
    await wrapper.get('[data-configuration-conflict] button').trigger('click');
    await flushPromises();
    expect(API.acwPolicy).toHaveBeenLastCalledWith('1');
    expect(wrapper.findAll('input[type="number"]')[0].element.value).toBe(
      '240'
    );
    expect(wrapper.get('[data-configuration-latest]').text()).toContain('300');
    expect(wrapper.get('[data-save-acw-policy]').element.disabled).toBe(true);
    await wrapper.get('[data-configuration-review]').setValue(true);
    expect(wrapper.get('[data-save-acw-policy]').element.disabled).toBe(false);
    await wrapper.findAll('input[type="number"]')[0].setValue(250);
    expect(wrapper.get('[data-save-acw-policy]').element.disabled).toBe(true);
    await wrapper.get('[data-configuration-review]').setValue(true);
    await wrapper.get('form').trigger('submit');
    expect(API.updateAcwPolicy).toHaveBeenLastCalledWith(
      1,
      { voice: 250, whatsapp: 180 },
      { voice_required: false, expected_revision: 'b'.repeat(64) }
    );
  });
  it('blocks a malformed current snapshot rather than using the compatibility omission', async () => {
    API.acwPolicy.mockResolvedValueOnce({ data: { item: item('') } });
    const wrapper = mount(AcwPolicyEditor, { props: { accountId: 1 } });
    await flushPromises();
    expect(wrapper.get('[data-save-acw-policy]').element.disabled).toBe(true);
    await wrapper.get('form').trigger('submit');
    expect(API.updateAcwPolicy).not.toHaveBeenCalled();
  });
  it('preserves the input and blocks retry when a fresh read is denied', async () => {
    API.acwPolicy.mockResolvedValueOnce({
      data: { item: item('a'.repeat(64)) },
    });
    API.acwPolicy.mockRejectedValueOnce({ response: { status: 401 } });
    API.updateAcwPolicy.mockRejectedValueOnce({
      response: { data: { error: 'stale_configuration_revision' } },
    });
    const wrapper = mount(AcwPolicyEditor, { props: { accountId: 1 } });
    await flushPromises();
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    await wrapper.get('[data-configuration-conflict] button').trigger('click');
    await flushPromises();
    expect(wrapper.get('[data-save-acw-policy]').element.disabled).toBe(true);
    expect(wrapper.find('[data-configuration-review]').exists()).toBe(false);
    expect(wrapper.findAll('input[type="number"]')[0].element.value).toBe(
      '180'
    );
    expect(wrapper.get('[data-configuration-conflict]').text()).toContain(
      'JRC_CONTACT_CENTER.COMMON.ERROR'
    );
  });
});
