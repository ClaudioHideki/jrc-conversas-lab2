import { flushPromises, mount } from '@vue/test-utils';
import { useRoute } from 'vue-router';
import DataImportsAPI from 'dashboard/api/dataImports';
import ImportReconciliationPanel from '../components/ImportReconciliationPanel.vue';

vi.mock('dashboard/api/dataImports', () => ({
  default: { reconciliation: vi.fn() },
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('vue-router', async () => {
  const { reactive } = await import('vue');
  const route = reactive({ params: { accountId: '1' } });
  return { useRoute: () => route };
});

const report = {
  data_import_id: 1,
  generated_at: '2026-11-02T12:00:00Z',
  source_checked: false,
  acceptance: 'not_reviewed',
  status: 'incomplete',
  entities: [
    {
      type: 'contact',
      source_total: null,
      difference: null,
      comparison: 'unknown',
      items: { pending: 0, processing: 0, imported: 0, skipped: 0, failed: 0 },
      mappings: {
        total: 0,
        valid: 0,
        missing: 0,
        cross_account: 0,
        unsupported: 0,
        skipped: 0,
        unmapped_items: 0,
      },
    },
  ],
  integrity: { foreign_account_mappings: 0 },
  logs: { errors: 0, failed: 0, skipped: 0 },
  attachments: {
    coverage: 'not_applicable',
    integrity_verified: false,
    referenced_messages: 0,
  },
};

afterEach(() => {
  vi.clearAllMocks();
  useRoute().params.accountId = '1';
});

it('queries only on request and presents an unknown source total without inventing zero', async () => {
  DataImportsAPI.reconciliation.mockResolvedValue({ data: report });
  const wrapper = mount(ImportReconciliationPanel, {
    props: { dataImportId: 1 },
  });
  expect(DataImportsAPI.reconciliation).not.toHaveBeenCalled();

  await wrapper.get('button').trigger('click');
  await flushPromises();

  expect(DataImportsAPI.reconciliation).toHaveBeenCalledExactlyOnceWith(1);
  const source = wrapper.get('[data-test="source-total-contact"]');
  expect(source.text()).toBe('DATA_IMPORTS.RECONCILIATION.UNKNOWN');
  expect(wrapper.text()).toContain('DATA_IMPORTS.RECONCILIATION.NOT_APPROVAL');
  expect(wrapper.findAll('button')).toHaveLength(1);
  wrapper.unmount();
});

it('clears a previous result when refreshing fails and sanitizes the error', async () => {
  DataImportsAPI.reconciliation
    .mockResolvedValueOnce({ data: report })
    .mockRejectedValueOnce({
      response: { status: 403 },
      message: 'private database detail',
    });
  const wrapper = mount(ImportReconciliationPanel, {
    props: { dataImportId: 1 },
  });
  await wrapper.get('button').trigger('click');
  await flushPromises();
  expect(wrapper.find('[data-test="source-total-contact"]').exists()).toBe(
    true
  );
  await wrapper.get('button').trigger('click');
  await flushPromises();

  expect(wrapper.get('[role="alert"]').text()).toBe(
    'DATA_IMPORTS.RECONCILIATION.ACCESS_DENIED'
  );
  expect(wrapper.find('[data-test="source-total-contact"]').exists()).toBe(
    false
  );
  expect(wrapper.text()).not.toContain('private database detail');
  wrapper.unmount();
});

it('ignores a late response after the account context changes and prevents duplicate queries', async () => {
  let finish;
  DataImportsAPI.reconciliation.mockReturnValue(
    new Promise(resolve => {
      finish = resolve;
    })
  );
  const wrapper = mount(ImportReconciliationPanel, {
    props: { dataImportId: 1 },
  });
  await wrapper.get('button').trigger('click');
  await wrapper.get('button').trigger('click');
  expect(DataImportsAPI.reconciliation).toHaveBeenCalledTimes(1);
  useRoute().params.accountId = '2';
  await flushPromises();
  finish({ data: report });
  await flushPromises();

  expect(wrapper.find('[data-test="source-total-contact"]').exists()).toBe(
    false
  );
  wrapper.unmount();
});

it('does not display a report returned for another import', async () => {
  DataImportsAPI.reconciliation.mockResolvedValue({
    data: { ...report, data_import_id: 2 },
  });
  const wrapper = mount(ImportReconciliationPanel, {
    props: { dataImportId: 1 },
  });
  await wrapper.get('button').trigger('click');
  await flushPromises();

  expect(wrapper.get('[role="alert"]').text()).toBe(
    'DATA_IMPORTS.RECONCILIATION.FAILED'
  );
  expect(wrapper.find('[data-test="source-total-contact"]').exists()).toBe(
    false
  );
  wrapper.unmount();
});
