import { beforeEach, describe, expect, it, vi } from 'vitest';
import { flushPromises, mount } from '@vue/test-utils';
import { reactive } from 'vue';
import { createI18n } from 'vue-i18n';
import Panel from '../RecipientPreferences.vue';

const mocks = vi.hoisted(() => ({
  session: null,
  recipientPreferences: vi.fn(),
  updateRecipientPreferences: vi.fn(),
}));
vi.mock('dashboard/api/serviceDeskCockpit', () => ({ default: mocks }));
vi.mock('../../composables/useServiceDesk', () => ({
  useServiceDesk: () => mocks.session,
}));
const result = (channels = ['email']) => ({
  contract_version: 1,
  account_id: '1',
  ticket_id: '8',
  channels,
});
const build = (visible = true) =>
  mount(Panel, {
    props: { ticket: { id: '8', permissions: { view_customer: visible } } },
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale: 'en',
          missingWarn: false,
          fallbackWarn: false,
        }),
      ],
      stubs: {
        Button: {
          props: ['label', 'disabled', 'type'],
          template:
            '<button :type="type" :disabled="disabled">{{ label }}</button>',
        },
      },
    },
  });

describe('Native recipient preferences use verified authorized readback', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.session = {
      state: reactive({
        status: 'ready',
        context: {
          account_id: '1',
          capabilities: { notifications: { manage: true } },
        },
      }),
    };
    mocks.recipientPreferences.mockResolvedValue(result());
    mocks.updateRecipientPreferences.mockResolvedValue({
      ...result([]),
      applied: true,
    });
  });

  it('does not read or edit a hidden customer', async () => {
    const wrapper = build(false);
    await flushPromises();
    expect(mocks.recipientPreferences).not.toHaveBeenCalled();
    expect(wrapper.find('form').exists()).toBe(false);
    wrapper.unmount();
  });

  it('persists explicit opt-out only after the native GET confirms it', async () => {
    const wrapper = build();
    await flushPromises();
    await wrapper.findAll('input')[0].setValue(false);
    mocks.recipientPreferences.mockResolvedValue(result([]));
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    expect(mocks.updateRecipientPreferences).toHaveBeenCalledWith(
      '1',
      '8',
      [],
      expect.any(AbortSignal)
    );
    expect(wrapper.emitted('updated')).toHaveLength(1);
    wrapper.unmount();
  });

  it('does not acknowledge mismatched readback and disables further blind retries', async () => {
    const wrapper = build();
    await flushPromises();
    await wrapper.findAll('input')[0].setValue(false);
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    expect(wrapper.emitted('updated')).toBeUndefined();
    expect(
      wrapper.find('button[type="submit"]').attributes('disabled')
    ).toBeDefined();
    wrapper.unmount();
  });

  it('hides the form immediately after current permission is revoked', async () => {
    const wrapper = build();
    await flushPromises();
    mocks.session.state.context.capabilities.notifications.manage = false;
    await flushPromises();
    expect(wrapper.find('form').exists()).toBe(false);
    expect(mocks.updateRecipientPreferences).not.toHaveBeenCalled();
    wrapper.unmount();
  });
});
