import { afterEach, describe, expect, it, vi } from 'vitest';
import { reactive } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import messages from 'dashboard/i18n/locale/pt_BR/jrcServiceDesk.json';
const holder = vi.hoisted(() => ({
  session: null,
  policies: vi.fn(),
  publish: vi.fn(),
  policy: vi.fn(),
}));
vi.mock('../../composables/useServiceDesk', () => ({
  useServiceDesk: () => holder.session,
}));
vi.mock('dashboard/api/serviceDeskLifecycle', () => ({ default: holder }));
import Editor from '../LifecyclePolicyEditor.vue';
let wrapper;
afterEach(() => {
  wrapper?.unmount();
  vi.clearAllMocks();
});

describe('Lifecycle publication busy state', () => {
  it('unlocks the editor after a confirmed write followed by list refresh', async () => {
    holder.session = {
      state: reactive({
        status: 'ready',
        context: {
          account_id: '1',
          user_id: '2',
          units: [{ id: '10' }],
          capabilities: { lifecycle_policies: { publish: true } },
        },
      }),
    };
    const row = {
      id: '3',
      account_id: '1',
      unit_id: '10',
      name: 'Suporte',
      service_id: null,
      enabled: false,
      version_id: '40',
      version: 1,
      digest: 'a'.repeat(64),
      definition: {
        schema_version: 2,
        transitions: [],
        sla: { mode: 'not_applicable' },
      },
    };
    const envelope = {
      contract_version: 1,
      account_id: '1',
      unit_id: '10',
      items: [row],
      meta: { page: 1, total: 1, per_page: 20 },
    };
    holder.policies.mockResolvedValue(envelope);
    const next = { ...row, version: 2, version_id: '41' };
    holder.publish.mockResolvedValue({ policy: next });
    holder.policy.mockResolvedValue({ policy: next });
    wrapper = mount(Editor, {
      global: {
        plugins: [
          createI18n({
            legacy: false,
            locale: 'pt_BR',
            messages: { pt_BR: messages },
          }),
        ],
        stubs: {
          Panel: { template: '<section><slot /></section>' },
          Button: {
            props: ['label', 'type', 'disabled'],
            template:
              '<button :type="type" :disabled="disabled">{{ label }}</button>',
          },
          ScopeBar: {
            emits: ['update:unitId'],
            template:
              "<button data-unit @click=\"$emit('update:unitId', '10')\">Unidade</button>",
          },
          ServiceSelect: true,
          State: true,
          Pagination: true,
          Input: true,
          TextArea: true,
          LifecycleVisualEditor: true,
          ClockThresholdEditor: true,
          ClockAutomationFields: true,
        },
      },
    });
    await wrapper.get('[data-unit]').trigger('click');
    await flushPromises();
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'Suporte v1')
      .trigger('click');
    holder.policies.mockResolvedValue({ ...envelope, items: [next] });
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(holder.publish).toHaveBeenCalledOnce();
    expect(holder.policy).toHaveBeenCalledOnce();
    expect(wrapper.text()).toContain(
      messages.JRC_SERVICE_DESK.LIFECYCLE.feedback.confirmed
    );
    const newButton = wrapper
      .findAll('button')
      .find(
        button =>
          button.text() === messages.JRC_SERVICE_DESK.LIFECYCLE.new_policy
      );
    expect(newButton.attributes('disabled')).toBeUndefined();
    await newButton.trigger('click');
    expect(wrapper.findComponent({ name: 'Input' }).props('modelValue')).toBe(
      ''
    );
  });
});
