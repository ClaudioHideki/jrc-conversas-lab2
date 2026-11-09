import { describe, expect, it, vi } from 'vitest';
import { mount } from '@vue/test-utils';
import { ref } from 'vue';
import VoiceCallSummary from './VoiceCallSummary.vue';
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key, locale: ref('pt_BR') }),
}));
describe('voice attendance summary', () => {
  it('keeps unknown identity and recording explicit instead of fabricating a recording indicator', () => {
    const wrapper = mount(VoiceCallSummary);
    expect(wrapper.text()).toContain('VOICE_V4.CUSTOMER_UNKNOWN');
    expect(wrapper.text()).toContain('VOICE_V4.RECORDING_UNKNOWN');
    expect(wrapper.find('[data-recording-active]').exists()).toBe(false);
  });
  it('shows the outbound destination, linked company and authorized server identity', () => {
    const wrapper = mount(VoiceCallSummary, {
      props: {
        call: {
          id: 3,
          direction: 'outbound',
          ani: 'extension',
          dnis: 'synthetic-customer',
          correlation_id: 'correlation-synthetic',
          queue: { name: 'Suporte' },
        },
        customer: {
          status: 'identified',
          contacts: [
            {
              name: 'Pessoa sintética',
              company: { name: 'Empresa sintética' },
            },
          ],
        },
      },
    });
    expect(wrapper.text()).toContain('synthetic-customer');
    expect(wrapper.text()).toContain('Empresa sintética');
    expect(wrapper.text()).toContain('correlation-synthetic');
  });
  it('makes a customer lookup failure visible without discarding the attendance identity', () => {
    const wrapper = mount(VoiceCallSummary, {
      props: {
        call: { id: 3, correlation_id: 'identity-synthetic' },
        customerStatus: 'error',
      },
    });
    expect(wrapper.get('[role=alert]').text()).toContain(
      'VOICE_V4.CUSTOMER_ERROR'
    );
    expect(wrapper.text()).toContain('identity-synthetic');
  });
});
