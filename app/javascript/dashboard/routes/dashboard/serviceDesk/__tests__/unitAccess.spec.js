import { beforeEach, afterEach, describe, expect, it, vi } from 'vitest';
import { reactive } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import StructureView from '../views/StructureView.vue';
import { membershipPage } from '../helpers/structure';
import messages from 'dashboard/i18n/locale/en/jrcServiceDesk.json';
import roles from 'dashboard/i18n/locale/en/customRole.json';

const holder = vi.hoisted(() => ({
  state: null,
  members: vi.fn(),
  list: vi.fn(),
  save: vi.fn(),
  record: vi.fn(),
  receipt: vi.fn(),
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({
    params: { accountId: '1' },
    query: { resource: 'unit_memberships' },
  }),
  useRouter: () => ({ push: vi.fn() }),
}));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({
    getters: {
      getCurrentUserID: '10',
      'accounts/isFeatureEnabledonAccount': () => true,
    },
  }),
}));
vi.mock('dashboard/composables/useServiceDeskStructure', () => ({
  useServiceDeskStructure: () => ({ state: holder.state, refresh: vi.fn() }),
}));
vi.mock('dashboard/api/serviceDeskStructure', () => ({ default: holder }));

const context = () => ({
  account_id: '1',
  user_id: '10',
  account_user_id: '15',
  available: true,
  capabilities: {
    units: true,
    operator_companies: true,
    unit_memberships: true,
  },
});
const base = {
  account_id: '1',
  revision: 'a'.repeat(64),
  active: true,
  name: 'Matriz',
  code: 'matriz',
};
const membership = active => ({
  ...base,
  id: '9',
  unit_id: '5',
  account_user_id: '25',
  active,
});
let persisted;
const directory = () => ({
  contract_version: 1,
  account_id: '1',
  unit: { ...base, id: '5', operator_company_id: '2' },
  operator_company: { ...base, id: '2', name: 'Grupo JRC' },
  items: [
    {
      id: '25',
      user_id: '20',
      name: 'Thiago Ribeiro LAB',
      role: 'agent',
      custom_role: null,
      capabilities: ['module_view'],
      membership: persisted,
    },
  ],
  meta: { total: 1, page: 1, per_page: 25 },
});
const envelope = () => ({
  contract_version: 1,
  account_id: '1',
  resource: 'unit_memberships',
  record: persisted,
  audit_id: '60',
});
const Button = {
  props: ['label', 'disabled', 'type'],
  template: '<button :disabled="disabled" :type="type">{{ label }}</button>',
};
const Input = {
  props: ['modelValue', 'label'],
  emits: ['update:modelValue'],
  template:
    '<input :aria-label="label" :value="modelValue" @input="$emit(\'update:modelValue\', $event.target.value)" />',
};
const Lookup = {
  emits: ['update:modelValue'],
  template:
    "<button data-unit @click=\"$emit('update:modelValue', '5')\">Matriz</button>",
};
const Panel = { template: '<div><slot /></div>' };
let wrapper;
const render = () => {
  wrapper = mount(StructureView, {
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale: 'en',
          messages: { en: { ...messages, ...roles } },
        }),
      ],
      stubs: {
        Button,
        Input,
        Lookup,
        Select: true,
        RouterLink: true,
        BaseTable: { template: '<div><slot name="row" /></div>' },
        BaseTableRow: Panel,
        BaseTableCell: Panel,
      },
    },
  });
};
const choose = async () => {
  await wrapper.get('[data-unit]').trigger('click');
  await flushPromises();
};
const press = async label => {
  await wrapper
    .findAll('button')
    .find(button => button.text() === label)
    .trigger('click');
  await flushPromises();
};

beforeEach(() => {
  persisted = null;
  holder.state = reactive({
    status: 'ready',
    visible: true,
    context: context(),
  });
  [holder.members, holder.save, holder.record, holder.receipt].forEach(mock =>
    mock.mockReset()
  );
  holder.members.mockImplementation(async () => directory());
  holder.record.mockImplementation(async () => envelope());
  holder.save.mockImplementation(async (_account, intent) => {
    const before = persisted;
    persisted = membership(intent.attributes.active);
    holder.receipt.mockResolvedValue({
      contract_version: 1,
      account_id: '1',
      receipt: {
        namespace: 'jrc_service_desk_structure_v1',
        id: '60',
        action: intent.action,
        account_id: '1',
        resource: 'unit_memberships',
        record_id: '9',
        author_user_id: '10',
        author_account_user_id: '15',
        fingerprint: 'a'.repeat(64),
        reason: intent.reason,
        occurred_at: '2026-09-28T18:00:00Z',
        before,
        after: persisted,
      },
    });
    return envelope();
  });
});
afterEach(() => {
  wrapper?.unmount();
  wrapper = null;
});

describe('Unit access using the structural API', () => {
  it('requires unit selection and shows people without memberships', async () => {
    render();
    expect(holder.members).not.toHaveBeenCalled();
    await choose();
    expect(wrapper.text()).toContain('Thiago Ribeiro LAB');
    expect(wrapper.text()).toContain('No membership');
    expect(wrapper.text()).toContain('Grupo JRC');
    expect(wrapper.text()).toContain(
      roles.CUSTOM_ROLE.PERMISSIONS.JRC_SERVICE_DESK_MODULE_VIEW
    );
  });

  it('creates, revokes, reactivates and reloads persisted access, confirming each audit and readback', async () => {
    render();
    await choose();
    const change = async label => {
      await press(label);
      await wrapper
        .get(
          `input[aria-label="${messages.JRC_SERVICE_DESK.STRUCTURE.reason}"]`
        )
        .setValue('Approved LAB test');
      await wrapper.get('form').trigger('submit');
      await flushPromises();
      expect(wrapper.text()).toContain(
        messages.JRC_SERVICE_DESK.STRUCTURE.states.confirmed
      );
    };
    await change('Grant access');
    await change('Revoke access');
    await change('Reactivate membership');
    expect(holder.save).toHaveBeenCalledTimes(3);
    expect(holder.receipt).toHaveBeenCalledTimes(3);
    expect(holder.record.mock.calls.length).toBe(5);
    wrapper.unmount();
    render();
    await choose();
    expect(wrapper.text()).toContain('Revoke access');
    expect(holder.save).toHaveBeenCalledTimes(3);
  });

  it('does not claim success when independent readback fails', async () => {
    render();
    await choose();
    await press('Grant access');
    await wrapper
      .get(`input[aria-label="${messages.JRC_SERVICE_DESK.STRUCTURE.reason}"]`)
      .setValue('Approved LAB test');
    holder.record.mockRejectedValue(new Error('Unavailable'));
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(wrapper.text()).toContain(
      messages.JRC_SERVICE_DESK.STRUCTURE.states.confirmation_pending
    );
    expect(wrapper.text()).not.toContain(
      messages.JRC_SERVICE_DESK.STRUCTURE.states.confirmed
    );
  });

  it('clears the directory when structural permission is revoked', async () => {
    render();
    await choose();
    holder.state.context = null;
    holder.state.status = 'denied';
    await flushPromises();
    expect(wrapper.text()).not.toContain('Thiago Ribeiro LAB');
    expect(wrapper.find('form').exists()).toBe(false);
  });

  it('rejects a foreign membership or wrong selected unit in a directory response', () => {
    persisted = { ...membership(true), account_user_id: '99' };
    expect(() => membershipPage(directory(), context(), 1, '5')).toThrow();
    persisted = null;
    expect(() => membershipPage(directory(), context(), 1, '6')).toThrow();
  });
});
