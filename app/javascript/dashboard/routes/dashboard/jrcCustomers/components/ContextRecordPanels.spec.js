import { computed, reactive } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import RecordsPanel from './RecordsPanel.vue';
import TimelinePanel from './TimelinePanel.vue';

const mocks = vi.hoisted(() => ({
  state: null,
  records: vi.fn(),
  contactRecords: vi.fn(),
  timeline: vi.fn(),
}));
vi.mock('dashboard/api/jrcCustomers', () => ({ default: mocks }));
vi.mock('../useCustomerMaster', () => ({
  useCustomerMaster: () => ({
    accountId: computed(() => mocks.state.account),
    identity: computed(() => `${mocks.state.account}:${mocks.state.role}`),
    date: value => value || '—',
    accountScopedRoute: (name, params, query) => ({
      name,
      params,
      ...(query ? { query } : {}),
    }),
  }),
}));
const rows = title => ({
  data: {
    payload: [{ id: 1, display_id: 99, title, status: 'open' }],
    meta: { total: 26, page: 1, per_page: 25 },
  },
});
const events = (id, title, cursor = null) => ({
  data: { payload: [{ id, source: 'audit', title }], next_cursor: cursor },
});
const render = (component, props) =>
  mount(component, {
    props,
    global: {
      stubs: {
        RouterLink: {
          name: 'RouterLink',
          props: ['to'],
          template: '<a><slot /></a>',
        },
      },
    },
  });
beforeEach(() => {
  vi.clearAllMocks();
  mocks.state = reactive({ account: 1, role: 'agent' });
  mocks.contactRecords.mockResolvedValue(
    rows('MOCK — Authorized contact conversation')
  );
  mocks.records.mockResolvedValue(
    rows('MOCK — Authorized company conversation')
  );
  mocks.timeline.mockResolvedValue(
    events(1, 'MOCK — Authorized event', 'opaque-cursor')
  );
});

it('uses the canonical contact endpoint and opens the conversation by its native display ID', async () => {
  const wrapper = render(RecordsPanel, {
    contactId: 42,
    kind: 'conversations',
  });
  await flushPromises();
  expect(mocks.contactRecords).toHaveBeenCalledWith(
    42,
    { kind: 'conversations', page: 1 },
    expect.objectContaining({ accountId: 1, signal: expect.any(AbortSignal) })
  );
  expect(mocks.records).not.toHaveBeenCalled();
  expect(wrapper.findComponent({ name: 'RouterLink' }).props('to')).toEqual({
    name: 'inbox_conversation',
    params: { conversation_id: 99 },
  });
  wrapper.unmount();
});

it('keeps the existing company endpoint and clears previous records after a current denial', async () => {
  const wrapper = render(RecordsPanel, {
    companyId: 77,
    kind: 'conversations',
  });
  await flushPromises();
  expect(mocks.records).toHaveBeenCalledWith(
    77,
    expect.any(Object),
    expect.objectContaining({ accountId: 1 })
  );
  mocks.records.mockRejectedValueOnce({
    response: { status: 401, data: { error: 'MOCK — scope denied' } },
  });
  await wrapper
    .findAll('button')
    .find(item => item.text() === 'Próxima')
    .trigger('click');
  await flushPromises();
  expect(wrapper.text()).not.toContain('Authorized company conversation');
  expect(wrapper.find('[role="alert"]').text()).toContain('scope denied');
  expect(wrapper.text()).not.toContain('Nenhum dado');
  wrapper.unmount();
});

it('passes the exact CRM record ID using the existing source screen query contract', async () => {
  mocks.contactRecords.mockResolvedValue({
    data: {
      payload: [{ id: 73, title: 'MOCK — Proposta canônica', status: 'draft' }],
      meta: { total: 1, page: 1, per_page: 25 },
    },
  });
  const wrapper = render(RecordsPanel, { contactId: 42, kind: 'proposals' });
  await flushPromises();
  expect(wrapper.findComponent({ name: 'RouterLink' }).props('to')).toEqual({
    name: 'crm_proposals',
    params: {},
    query: { proposalId: 73 },
  });
  wrapper.unmount();
});

it('resets paging on a role change and discards a previous page response', async () => {
  const wrapper = render(RecordsPanel, {
    contactId: 42,
    kind: 'conversations',
  });
  await flushPromises();
  let resolveOld;
  mocks.contactRecords.mockReturnValueOnce(
    new Promise(resolve => {
      resolveOld = resolve;
    })
  );
  await wrapper
    .findAll('button')
    .find(item => item.text() === 'Próxima')
    .trigger('click');
  mocks.contactRecords.mockResolvedValue(rows('MOCK — New role record'));
  mocks.state.role = 'changed';
  await flushPromises();
  resolveOld(rows('PRIVATE_OLD_ROLE_PAGE'));
  await flushPromises();
  expect(mocks.contactRecords).toHaveBeenLastCalledWith(
    42,
    expect.objectContaining({ page: 1 }),
    expect.objectContaining({ accountId: 1 })
  );
  expect(wrapper.text()).toContain('New role record');
  expect(wrapper.text()).not.toContain('PRIVATE_OLD_ROLE_PAGE');
  wrapper.unmount();
});

it('uses the native opaque cursor for contact history and appends authorized events', async () => {
  const wrapper = render(TimelinePanel, {
    resourceId: 42,
    resourceType: 'contacts',
  });
  await flushPromises();
  mocks.timeline.mockResolvedValueOnce(events(2, 'MOCK — Second event'));
  await wrapper
    .findAll('button')
    .find(item => item.text() === 'Carregar mais')
    .trigger('click');
  await flushPromises();
  expect(mocks.timeline).toHaveBeenLastCalledWith(
    42,
    { cursor: 'opaque-cursor' },
    'contacts',
    expect.objectContaining({ accountId: 1, signal: expect.any(AbortSignal) })
  );
  expect(wrapper.findAll('ol li')).toHaveLength(2);
  expect(wrapper.text()).toContain('Authorized event');
  expect(wrapper.text()).toContain('Second event');
  wrapper.unmount();
});

it('clears cached history and its cursor when access is denied while loading more', async () => {
  const wrapper = render(TimelinePanel, {
    resourceId: 42,
    resourceType: 'contacts',
  });
  await flushPromises();
  mocks.timeline.mockRejectedValueOnce({
    response: { status: 403, data: { error: 'MOCK — history denied' } },
  });
  await wrapper
    .findAll('button')
    .find(item => item.text() === 'Carregar mais')
    .trigger('click');
  await flushPromises();
  expect(wrapper.findAll('ol li')).toHaveLength(0);
  expect(wrapper.text()).not.toContain('Authorized event');
  expect(wrapper.text()).not.toContain('Carregar mais');
  expect(wrapper.find('[role="alert"]').text()).toContain('history denied');
  wrapper.unmount();
});

it('discards history from an old account and restarts the cursor for the new context', async () => {
  let resolveOld;
  mocks.timeline.mockReturnValueOnce(
    new Promise(resolve => {
      resolveOld = resolve;
    })
  );
  const wrapper = render(TimelinePanel, {
    resourceId: 42,
    resourceType: 'contacts',
  });
  mocks.timeline.mockRejectedValueOnce({
    response: { status: 404, data: { error: 'MOCK — unavailable subject' } },
  });
  mocks.state.account = 2;
  await flushPromises();
  resolveOld(events(1, 'PRIVATE_OLD_ACCOUNT_EVENT', 'private-old-cursor'));
  await flushPromises();
  expect(mocks.timeline).toHaveBeenLastCalledWith(
    42,
    { cursor: undefined },
    'contacts',
    expect.objectContaining({ accountId: 2 })
  );
  expect(wrapper.text()).not.toContain('PRIVATE_OLD_ACCOUNT_EVENT');
  expect(wrapper.text()).not.toContain('Carregar mais');
  wrapper.unmount();
});
