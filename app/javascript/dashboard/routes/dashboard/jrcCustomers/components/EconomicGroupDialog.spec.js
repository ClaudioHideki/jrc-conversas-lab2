import { computed, reactive } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import GroupDialog from './EconomicGroupDialog.vue';
import Members from './EconomicGroupMembers.vue';
const mocks = vi.hoisted(() => ({
  state: null,
  economicGroup: vi.fn(),
  saveEconomicGroup: vi.fn(),
  deleteEconomicGroup: vi.fn(),
}));
vi.mock('dashboard/api/jrcCustomers', () => ({ default: mocks }));
vi.mock('../useCustomerMaster', () => ({
  useCustomerMaster: () => ({
    accountId: computed(() => mocks.state.account),
    identity: computed(() => `${mocks.state.account}:${mocks.state.admin}`),
    canAdmin: computed(() => mocks.state.admin),
  }),
}));
const record = {
  id: 7,
  name: 'MOCK — Grupo corporativo',
  description: 'Descrição real',
  revision: '2026-11-03T10:00:00.000000Z',
  member_count: 2,
  can_manage: true,
  principal_company: { id: 8, name: 'MOCK — Principal' },
};
const render = props =>
  mount(GroupDialog, {
    props,
    global: {
      stubs: {
        Dialog: {
          setup: (_, { expose }) => expose({ open: vi.fn(), close: vi.fn() }),
          template: '<section><slot /></section>',
        },
        EconomicGroupMembers: true,
        EconomicGroupHistory: true,
      },
    },
  });
beforeEach(() => {
  vi.clearAllMocks();
  mocks.state = reactive({ account: 1, admin: true });
  mocks.economicGroup.mockResolvedValue({ data: { payload: record } });
  mocks.saveEconomicGroup.mockResolvedValue({ data: { payload: record } });
});

it('enables company operations only after the server persists a new group', async () => {
  const wrapper = render();
  await flushPromises();
  expect(wrapper.findAll('nav button')[1].attributes('disabled')).toBeDefined();
  await wrapper.find('input').setValue('MOCK — Novo grupo');
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  expect(mocks.saveEconomicGroup).toHaveBeenCalledWith(
    expect.objectContaining({ name: 'MOCK — Novo grupo' }),
    null,
    { accountId: 1 }
  );
  expect(wrapper.findComponent(Members).props('group').id).toBe(7);
  expect(wrapper.emitted('saved')).toHaveLength(1);
  wrapper.unmount();
});

it('keeps description drafts and the authenticated account on a rejected revision', async () => {
  mocks.saveEconomicGroup.mockRejectedValue({
    response: { data: { error: 'MOCK — Revisão desatualizada' } },
  });
  const wrapper = render({ groupId: 7 });
  await flushPromises();
  await wrapper.find('textarea').setValue('MOCK — Preservar rascunho');
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  expect(wrapper.find('textarea').element.value).toBe(
    'MOCK — Preservar rascunho'
  );
  expect(mocks.saveEconomicGroup).toHaveBeenCalledWith(
    expect.objectContaining({ revision: record.revision }),
    7,
    { accountId: 1 }
  );
  expect(wrapper.emitted('saved')).toBeUndefined();
  expect(wrapper.text()).toContain('MOCK — Revisão desatualizada');
  wrapper.unmount();
});

it('does not turn a failed group lookup into a create or expose administrator operations to readers', async () => {
  mocks.economicGroup.mockRejectedValue({
    response: { data: { error: 'MOCK — Não encontrado' } },
  });
  const missing = render({ groupId: 99 });
  await flushPromises();
  expect(missing.find('form').exists()).toBe(false);
  expect(mocks.saveEconomicGroup).not.toHaveBeenCalled();
  missing.unmount();
  mocks.economicGroup.mockResolvedValue({ data: { payload: record } });
  mocks.state.admin = false;
  const reader = render({ groupId: 7 });
  await flushPromises();
  expect(reader.find('button[type="submit"]').exists()).toBe(false);
  mocks.state.account = 2;
  await flushPromises();
  expect(reader.emitted('close')).toHaveLength(1);
  reader.unmount();
});

it('changes only the optional principal and retains an unsaved description', async () => {
  const wrapper = render({ groupId: 7 });
  await flushPromises();
  await wrapper.find('textarea').setValue('MOCK — Rascunho');
  await wrapper.findAll('nav button')[1].trigger('click');
  wrapper.findComponent(Members).vm.$emit('principal', 12);
  await flushPromises();
  expect(mocks.saveEconomicGroup).toHaveBeenCalledWith(
    { principal_company_id: 12, revision: record.revision },
    7,
    { accountId: 1 }
  );
  await wrapper.findAll('nav button')[0].trigger('click');
  expect(wrapper.find('textarea').element.value).toBe('MOCK — Rascunho');
  wrapper.unmount();
});
