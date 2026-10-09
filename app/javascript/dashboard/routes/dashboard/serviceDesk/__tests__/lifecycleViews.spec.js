import { afterEach, describe, it, expect, vi } from 'vitest';
import { reactive } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import messages from 'dashboard/i18n/locale/pt_BR/jrcServiceDesk.json';
import { lcContext, lcTicket, lcPayload } from './lifecycleCases.js';
const holder = vi.hoisted(() => ({
  session: null,
  read: vi.fn(),
  apply: vi.fn(),
}));
vi.mock('../composables/useServiceDesk', () => ({
  useServiceDesk: () => holder.session,
}));
vi.mock('dashboard/api/serviceDeskLifecycle', () => ({
  default: {
    read: (...args) => holder.read(...args),
    apply: (...args) => holder.apply(...args),
  },
}));
import LifecyclePanel from '../components/LifecyclePanel.vue';
import LifecyclePolicyEditor from '../components/LifecyclePolicyEditor.vue';
const Button = {
  props: ['label', 'disabled'],
  template: '<button :disabled="disabled">{{ label }}</button>',
};
const Panel = { template: '<section><slot /></section>' };
let wrapper;
afterEach(() => {
  wrapper?.unmount();
  vi.clearAllMocks();
});
const globals = () => ({
  plugins: [
    createI18n({
      legacy: false,
      locale: 'pt_BR',
      messages: { pt_BR: messages },
    }),
  ],
  stubs: {
    Panel,
    Button,
    State: true,
    Select: true,
    Input: true,
    TextArea: true,
    Pagination: true,
  },
});
describe('CP4-D01 native Vue wiring - requires native execution', () => {
  it('associates the native expected boolean requirement with its actual checkbox without executing a transition', async () => {
    holder.session = {
      state: reactive({ status: 'ready', context: lcContext() }),
      operations: { state: reactive({ revision: 0 }) },
    };
    holder.read.mockResolvedValue(lcPayload());
    wrapper = mount(LifecyclePanel, {
      props: { ticket: lcTicket() },
      global: globals(),
    });
    await flushPromises();
    wrapper
      .findComponent({ name: 'Select' })
      .vm.$emit('update:modelValue', 'resolve');
    await flushPromises();
    expect(
      wrapper.get('[data-testid="lifecycle-expected-value"]').text()
    ).toContain('true');
    expect(
      wrapper
        .get('[data-testid="lifecycle-boolean-field"] input')
        .attributes('type')
    ).toBe('checkbox');
    expect(
      wrapper.get('[data-testid="lifecycle-boolean-field"]').text()
    ).toContain('Fixture accepted');
    expect(holder.apply).not.toHaveBeenCalled();
  });
  it('shows no operational button when no applicable policy is returned', async () => {
    holder.session = {
      state: reactive({ status: 'ready', context: lcContext() }),
      operations: { state: reactive({ revision: 0 }) },
    };
    holder.read.mockResolvedValue(
      lcPayload({
        policy: null,
        options: [],
        unavailable_reason: 'no_applicable_policy',
      })
    );
    wrapper = mount(LifecyclePanel, {
      props: { ticket: lcTicket() },
      global: globals(),
    });
    await flushPromises();
    expect(wrapper.text()).toContain(
      messages.JRC_SERVICE_DESK.LIFECYCLE.no_applicable_policy
    );
    expect(holder.apply).not.toHaveBeenCalled();
    expect(wrapper.find('form').exists()).toBe(false);
  });
  it('does not convert calendar dependency into an operational SLA', async () => {
    holder.session = {
      state: reactive({ status: 'ready', context: lcContext() }),
      operations: { state: reactive({ revision: 0 }) },
    };
    holder.read.mockResolvedValue(
      lcPayload({
        options: [],
        unavailable_reason: 'calendar_snapshot_required',
      })
    );
    wrapper = mount(LifecyclePanel, {
      props: { ticket: lcTicket() },
      global: globals(),
    });
    await flushPromises();
    expect(wrapper.text()).toContain(
      messages.JRC_SERVICE_DESK.LIFECYCLE.calendar_snapshot_required
    );
    expect(holder.session.operations.state.revision).toBe(0);
  });
  it('hides policy administration without backend capability even when a local role says administrator', async () => {
    const ctx = lcContext();
    ctx.role = 'administrator';
    ctx.capabilities.settings = { index: false };
    holder.session = { state: reactive({ status: 'ready', context: ctx }) };
    wrapper = mount(LifecyclePolicyEditor, { global: globals() });
    await flushPromises();
    expect(wrapper.find('form').exists()).toBe(false);
    expect(holder.read).not.toHaveBeenCalled();
  });
  it('discards lifecycle content when context is revoked', async () => {
    holder.session = {
      state: reactive({ status: 'ready', context: lcContext() }),
      operations: { state: reactive({ revision: 0 }) },
    };
    holder.read.mockResolvedValue(lcPayload());
    wrapper = mount(LifecyclePanel, {
      props: { ticket: lcTicket() },
      global: globals(),
    });
    await flushPromises();
    holder.session.state.status = 'denied';
    holder.session.state.context = null;
    await flushPromises();
    expect(wrapper.find('form').exists()).toBe(false);
    expect(holder.apply).not.toHaveBeenCalled();
  });
});
