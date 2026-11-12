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
