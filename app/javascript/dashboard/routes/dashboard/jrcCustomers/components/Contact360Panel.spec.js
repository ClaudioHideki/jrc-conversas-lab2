import { computed, reactive } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import Panel from './Contact360Panel.vue';

const mocks = vi.hoisted(() => ({
  state: null,
  contact: vi.fn(),
  contactOverview: vi.fn(),
}));
vi.mock('dashboard/api/jrcCustomers', () => ({ default: mocks }));
vi.mock('../useCustomerMaster', () => ({
  useCustomerMaster: () => ({
    accountId: computed(() => mocks.state.account),
    identity: computed(() => `${mocks.state.account}:${mocks.state.role}`),
    date: value => value || '—',
  }),
}));
vi.mock('dashboard/composables/usePolicy', () => ({
  usePolicy: () => ({ checkPermissions: () => false }),
}));
const person = {
  id: 42,
  name: 'MOCK — Pessoa canônica',
  company_id: null,
  email: 'mock@example.test',
  registration_status: 'registered',
};
const summary = {
  conversations_open: 1,
  opportunities: 2,
  pending_activities: 3,
  capabilities: { crm: true },
};
const render = () =>
  mount(Panel, {
    props: { contactId: 42 },
    global: {
      stubs: {
        MasterTicketAction: true,
        MasterContactPanel: true,
        RecordsPanel: true,
        TimelinePanel: true,
        CompanyContactHistoryPanel: true,
        CompanyDetailsDialog: true,
        ComposeConversation: true,
        VoiceCallButton: true,
      },
    },
  });
beforeEach(() => {
  vi.clearAllMocks();
  mocks.state = reactive({ account: 1, role: 'agent' });
  mocks.contact.mockResolvedValue({
    data: { payload: structuredClone(person) },
  });
  mocks.contactOverview.mockResolvedValue({ data: structuredClone(summary) });
});

it('keeps the six approved tabs and opens the canonical link history only after choosing its section', async () => {
  const wrapper = render();
  await flushPromises();
  await wrapper
    .findAll('button')
    .find(item => item.text() === 'Histórico')
    .trigger('click');
  expect(
    wrapper.findComponent({ name: 'CompanyContactHistoryPanel' }).exists()
  ).toBe(false);
  await wrapper
    .findAll('button')
    .find(item => item.text() === 'Histórico de vínculos')
    .trigger('click');
  expect(
    wrapper
      .findComponent({ name: 'CompanyContactHistoryPanel' })
      .props('contactId')
  ).toBe(42);
  expect(wrapper.findComponent({ name: 'TimelinePanel' }).exists()).toBe(false);
  wrapper.unmount();
});

it('opens six authorized tabs using the exact contact and mounts source panels only after selection', async () => {
  const wrapper = render();
  await flushPromises();
  expect(mocks.contact).toHaveBeenCalledWith(
    42,
    expect.objectContaining({ accountId: 1, signal: expect.any(AbortSignal) })
  );
  expect(wrapper.find('nav').findAll('button')).toHaveLength(6);
  expect(wrapper.findComponent({ name: 'RecordsPanel' }).exists()).toBe(false);
  await wrapper
    .findAll('button')
    .find(item => item.text() === 'Atendimento')
    .trigger('click');
  expect(wrapper.findComponent({ name: 'RecordsPanel' }).props()).toMatchObject(
    { contactId: 42, kind: 'conversations' }
  );
  await wrapper
    .findAll('button')
    .find(item => item.text() === 'Empresa e Vínculos')
    .trigger('click');
  expect(
    wrapper.findComponent({ name: 'MasterContactPanel' }).props()
  ).toMatchObject({ contactId: 42, expandedByDefault: true });
  await wrapper
    .findAll('button')
    .find(item => item.text() === 'Histórico')
    .trigger('click');
  expect(
    wrapper.findComponent({ name: 'TimelinePanel' }).props()
  ).toMatchObject({ resourceId: 42, resourceType: 'contacts' });
  wrapper.unmount();
});

it('omits unavailable CRM tabs instead of presenting unauthorized zero values', async () => {
  mocks.contactOverview.mockResolvedValue({
    data: { conversations_open: 0, capabilities: {} },
  });
  const wrapper = render();
  await flushPromises();
  expect(wrapper.find('nav').findAll('button')).toHaveLength(4);
  expect(wrapper.findAll('button').map(item => item.text())).not.toContain(
    'CRM'
  );
  expect(wrapper.text()).not.toContain('Oportunidades');
  wrapper.unmount();
});

it('discards a previous account response and clears details after a current denial', async () => {
  let resolveOld;
  mocks.contact.mockReturnValueOnce(
    new Promise(resolve => {
      resolveOld = resolve;
    })
  );
  const wrapper = render();
  mocks.contact.mockRejectedValueOnce({
    response: { status: 403, data: { error: 'MOCK — denied' } },
  });
  mocks.state.account = 2;
  await flushPromises();
  resolveOld({ data: { payload: structuredClone(person) } });
  await flushPromises();
  expect(wrapper.text()).not.toContain(person.name);
  expect(wrapper.emitted('denied')).toHaveLength(1);
  expect(wrapper.find('[role="alert"]').exists()).toBe(true);
  wrapper.unmount();
});
