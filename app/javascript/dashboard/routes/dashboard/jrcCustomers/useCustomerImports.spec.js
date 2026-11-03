import { computed, reactive } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import { createRouter, createMemoryHistory } from 'vue-router';
import { useCustomerImports } from './useCustomerImports';

const mocks = vi.hoisted(() => ({
  state: null,
  importMetadata: vi.fn(),
  importRun: vi.fn(),
  uploadImport: vi.fn(),
  previewImport: vi.fn(),
  applyImport: vi.fn(),
  importRecords: vi.fn(),
  importRuns: vi.fn(),
  importTemplate: vi.fn(),
  importErrorsFile: vi.fn(),
}));
vi.mock('dashboard/api/jrcCustomers', () => ({ default: mocks }));
vi.mock('./useCustomerMaster', () => ({
  useCustomerMaster: () => ({
    accountId: computed(() => mocks.state.account),
    identity: computed(() => `${mocks.state.account}:${mocks.state.role}`),
    date: value => value,
  }),
}));
const pending = {
  data: {
    payload: {
      id: 17,
      filename: 'MOCK.csv',
      kind: 'contacts',
      status: 'pending',
      can_review: true,
    },
    file: { headers: ['name'], fields: ['contact.name'], row_count: 1 },
    column_mapping: { name: 'contact.name' },
    import_options: { existing: 'skip', confirmations: {} },
  },
};
const completed = {
  data: {
    payload: {
      ...pending.data.payload,
      status: 'completed',
      can_review: false,
      stats: { applied_entities: 1 },
    },
  },
};
const rows = {
  data: {
    payload: [{ id: 1, entity: 'contact', record_id: 41, name: 'MOCK person' }],
    meta: { page: 1, per_page: 25, total: 26 },
  },
};
const render = async (query = '') => {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [{ path: '/imports', component: { template: '<div />' } }],
  });
  await router.push(`/imports${query}`);
  const wrapper = mount(
    {
      setup() {
        return useCustomerImports();
      },
      template: '<div />',
    },
    { global: { plugins: [router] } }
  );
  await flushPromises();
  return { wrapper, router, state: wrapper.vm };
};
beforeEach(() => {
  vi.resetAllMocks();
  mocks.state = reactive({ account: 1, role: 'administrator' });
  mocks.importMetadata.mockResolvedValue({
    data: { available_kinds: ['companies', 'contacts', 'both'] },
  });
  mocks.importRun.mockResolvedValue(pending);
  mocks.uploadImport.mockResolvedValue(pending);
  mocks.previewImport.mockResolvedValue({
    data: {
      payload: pending.data.payload,
      rows: [],
      errors: [],
      token: 'MOCK_SIGNED_REVIEW',
    },
  });
  mocks.applyImport.mockResolvedValue(completed);
  mocks.importRecords.mockResolvedValue(rows);
  mocks.importRuns.mockResolvedValue({
    data: { payload: [], meta: { page: 1, per_page: 20, total: 0 } },
  });
});

it('uploads to an explicit account and restores the durable run through route navigation without applying it', async () => {
  const { wrapper, router, state } = await render('?kind=contacts');
  expect(state.kind).toBe('contacts');
  state.file = new File(['name\nMOCK'], 'MOCK.csv', { type: 'text/csv' });
  await state.upload();
  await flushPromises();
  expect(router.currentRoute.value.query.import_id).toBe('17');
  expect(mocks.uploadImport).toHaveBeenCalledWith(
    expect.any(File),
    'contacts',
    '',
    { accountId: 1, signal: expect.any(AbortSignal) }
  );
  expect(state.tab).toBe('mapping');
  expect(state.mapping).toEqual({ name: 'contact.name' });
  expect(mocks.applyImport).not.toHaveBeenCalled();
  wrapper.unmount();
});

it('invalidates a preview when mapping or existing-record choices change and never persists its token in the URL', async () => {
  const { wrapper, router, state } = await render('?import_id=17');
  await state.inspect();
  expect(state.preview.token).toBe('MOCK_SIGNED_REVIEW');
  expect(state.tab).toBe('preview');
  expect(router.currentRoute.value.fullPath).not.toContain(
    'MOCK_SIGNED_REVIEW'
  );
  state.options.existing = 'update';
  await flushPromises();
  expect(state.preview).toBeNull();
  await state.apply();
  expect(mocks.applyImport).not.toHaveBeenCalled();
  wrapper.unmount();
});

it('applies only a reviewed token, shows the server result and resumes the same outcome after a reload', async () => {
  const { wrapper, router, state } = await render('?import_id=17');
  await state.inspect();
  await state.apply();
  expect(mocks.applyImport).toHaveBeenCalledWith(
    17,
    'MOCK_SIGNED_REVIEW',
    expect.objectContaining({ accountId: 1 })
  );
  expect(state.run.status).toBe('completed');
  expect(state.tab).toBe('result');
  expect(state.records.payload[0].record_id).toBe(41);
  wrapper.unmount();
  mocks.importRun.mockResolvedValue(completed);
  const resumed = await render(
    `?import_id=${router.currentRoute.value.query.import_id}`
  );
  expect(resumed.state.tab).toBe('result');
  expect(resumed.state.preview).toBeNull();
  expect(mocks.applyImport).toHaveBeenCalledTimes(1);
  resumed.wrapper.unmount();
});

it('keeps a denied or stale application unsuccessful and supports reviewing it again', async () => {
  const { wrapper, state } = await render('?import_id=17');
  await state.inspect();
  mocks.applyImport.mockRejectedValue({
    response: { status: 409, data: { error: 'MOCK review required' } },
  });
  await state.apply();
  expect(state.run.status).toBe('pending');
  expect(state.error).toBe('MOCK review required');
  expect(state.tab).toBe('preview');
  expect(mocks.importRecords).not.toHaveBeenCalled();
  await state.inspect();
  expect(state.error).toBe('');
  expect(state.preview.token).toBe('MOCK_SIGNED_REVIEW');
  wrapper.unmount();
});

it('uses bounded server pages for history and outcomes instead of fabricating local totals', async () => {
  mocks.importRun.mockResolvedValue(completed);
  const { wrapper, state } = await render('?import_id=17');
  await state.pageRecords(2);
  expect(mocks.importRecords).toHaveBeenLastCalledWith(
    17,
    'rows',
    { page: 2, per_page: 25 },
    expect.objectContaining({ accountId: 1 })
  );
  state.filters.q = 'MOCK';
  await state.loadHistory(3);
  expect(mocks.importRuns).toHaveBeenLastCalledWith(
    { q: 'MOCK', kind: '', status: '', page: 3, per_page: 20 },
    expect.objectContaining({ accountId: 1 })
  );
  expect(state.tab).toBe('history');
  wrapper.unmount();
});

it('clears old results and ignores late responses after an account or permission change', async () => {
  const { wrapper, state } = await render('?import_id=17');
  let resolveOld;
  mocks.importRuns.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        resolveOld = resolve;
      })
  );
  const oldRequest = state.loadHistory();
  mocks.importMetadata.mockResolvedValue({ data: { available_kinds: [] } });
  mocks.state.account = 2;
  await flushPromises();
  resolveOld({
    data: {
      payload: [{ id: 99, filename: 'PRIVATE_OLD_ACCOUNT' }],
      meta: { total: 1 },
    },
  });
  await oldRequest;
  expect(state.canImport).toBe(false);
  expect(state.run).toBeNull();
  expect(state.history.payload).toEqual([]);
  expect(mocks.importMetadata).toHaveBeenLastCalledWith({
    accountId: 2,
    signal: expect.any(AbortSignal),
  });
  wrapper.unmount();
});
