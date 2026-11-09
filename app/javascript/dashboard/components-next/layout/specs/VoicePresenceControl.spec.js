import { beforeEach, describe, expect, it, vi } from 'vitest';
import { mount } from '@vue/test-utils';
import VoicePresenceControl from '../VoicePresenceControl.vue';
import { voiceShellState } from 'dashboard/routes/dashboard/webphone/voiceShell';
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
beforeEach(() => {
  voiceShellState.value = null;
});
describe('single top-level presence control', () => {
  it('preserves the native presence UI when Contact Center is disabled or unauthorized', () => {
    const wrapper = mount(VoicePresenceControl, {
      props: { accountId: 7, userId: 91 },
      slots: { default: '<button>native-presence</button>' },
    });
    expect(wrapper.text()).toContain('native-presence');
  });
  it('shows the persisted pause rather than SIP registration and hides another Account state', async () => {
    voiceShellState.value = {
      accountId: 7,
      userId: 91,
      context: { capabilities: { operate: true } },
      agent: { state: 'paused', reason_code: 'lunch' },
    };
    const wrapper = mount(VoicePresenceControl, {
      props: { accountId: 7, userId: 91 },
      global: {
        stubs: { Dialog: { methods: { open() {} }, template: '<div />' } },
      },
    });
    expect(wrapper.text()).toContain(
      'JRC_CONTACT_CENTER.AGENT.PAUSE_REASONS.lunch'
    );
    expect(wrapper.text()).not.toContain('SOFTPHONE.INBOX.REGISTERED');
    await wrapper.setProps({ accountId: 8 });
    expect(wrapper.text()).not.toContain(
      'JRC_CONTACT_CENTER.AGENT.PAUSE_REASONS.lunch'
    );
  });
});
