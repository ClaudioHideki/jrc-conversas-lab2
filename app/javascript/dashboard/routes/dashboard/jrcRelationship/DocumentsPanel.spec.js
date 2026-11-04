import { reactive } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import { beforeEach, expect, it, vi } from 'vitest';
import DocumentsPanel from './DocumentsPanel.vue';
const mocks = vi.hoisted(() => ({
  route: null,
  store: null,
  documents: vi.fn(),
  document: vi.fn(),
  updateDocumentMetadata: vi.fn(),
}));
vi.mock('vue-router', () => ({ useRoute: () => mocks.route }));
vi.mock('vuex', () => ({ useStore: () => mocks.store }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/api/jrcRelationship', () => ({ default: mocks }));
const v = {
  id: 2,
  number: 2,
  uploaded_by: { id: 7, name: 'Synthetic author' },
  uploaded_at: '2026-11-03',
  valid_until: '2025-11-03',
  expired: true,
  scan_state: 'pending',
  download_available: false,
  change_reason: 'Real version reason',
  filename: 'Synthetic.txt',
};
const record = {
  id: 1,
  title: 'Synthetic document',
  status: 'active',
  category: 'registration',
  portfolio_owner: { id: 8, name: 'Synthetic portfolio owner' },
  versions: [v],
};
const render = () =>
  mount(DocumentsPanel, {
    props: {
      assignmentId: 3,
      metadata: {
        can_manage_documents: false,
        formatting: { locale: 'pt-BR' },
      },
    },
    global: {
      stubs: { DocumentUploadDialog: true, DocumentMetadataDialog: true },
    },
  });
beforeEach(() => {
  mocks.route = reactive({ params: { accountId: '1' } });
  mocks.store = { getters: reactive({ getCurrentUserID: 7 }) };
  mocks.documents.mockReset().mockResolvedValue({
    data: { payload: [record], meta: { total: 1, per_page: 20 } },
  });
  mocks.document.mockReset().mockResolvedValue({
    data: { ...record, versions_meta: { total: 1, page: 1, per_page: 20 } },
  });
});
it('separates the historical author, portfolio owner, document status and quarantine', async () => {
  const wrapper = render();
  await flushPromises();
  expect(wrapper.text()).toContain('Synthetic author');
  expect(wrapper.text()).toContain('Synthetic portfolio owner');
  expect(wrapper.text()).toContain('RELATIONSHIP.V2.DOCS.STATUSES.active');
  expect(
    wrapper
      .findAll('button')
      .find(button => button.text() === 'RELATIONSHIP.V2.DOCS.DOWNLOAD').element
      .disabled
  ).toBe(true);
  expect(
    wrapper
      .findAll('button')
      .some(button => button.text() === 'RELATIONSHIP.V2.DOCS.UPLOAD')
  ).toBe(false);
  wrapper.unmount();
});
it('opens preserved version history with authors and validity and clears it on denial', async () => {
  const wrapper = render();
  await flushPromises();
  await wrapper
    .findAll('button')
    .find(button => button.text() === 'RELATIONSHIP.V2.DOCS.VERSIONS')
    .trigger('click');
  await flushPromises();
  expect(wrapper.text()).toContain('Real version reason');
  expect(
    wrapper
      .findAll('button')
      .filter(button => button.text() === 'RELATIONSHIP.V2.DOCS.DOWNLOAD')
      .every(button => button.element.disabled)
  ).toBe(true);
  mocks.documents.mockRejectedValue({ response: { status: 403 } });
  await wrapper
    .findAll('button')
    .find(button => button.text() === 'RELATIONSHIP.REFRESH')
    .trigger('click');
  await flushPromises();
  expect(wrapper.text()).not.toContain('Synthetic document');
  expect(wrapper.text()).not.toContain('Synthetic author');
  wrapper.unmount();
});

it('persists metadata through the authenticated API and reloads the native read model', async () => {
  const wrapper = render();
  await wrapper.setProps({
    metadata: { can_manage_documents: true, formatting: { locale: 'pt-BR' } },
  });
  await flushPromises();
  mocks.updateDocumentMetadata.mockResolvedValue({ data: {} });
  await wrapper
    .findAll('button')
    .find(row => row.text() === 'RELATIONSHIP.V2.DOCS.METADATA')
    .trigger('click');
  const dialog = wrapper.findComponent({ name: 'DocumentMetadataDialog' });
  const fields = {
    responsible_id: 8,
    revision: 0,
    status: 'active',
    reason: 'Reviewed documentary ownership',
  };
  dialog.vm.$emit('save', fields);
  await flushPromises();
  expect(mocks.updateDocumentMetadata).toHaveBeenCalledWith('1', 1, fields);
  expect(mocks.documents.mock.calls.length).toBeGreaterThan(1);
  expect(
    wrapper.findComponent({ name: 'DocumentMetadataDialog' }).exists()
  ).toBe(false);
  wrapper.unmount();
});

it('shows the native scoped catalog and clears it when access is revoked', async () => {
  mocks.documents.mockResolvedValue({
    data: {
      payload: [record],
      meta: { total: 1, per_page: 20 },
      requirements: {
        scope_key: 'account',
        configuration_version: 2,
        entries: [
          {
            code: 'proof',
            title: 'Required proof',
            category: 'registration',
            state: 'missing',
          },
        ],
      },
    },
  });
  const wrapper = render();
  await flushPromises();
  expect(wrapper.text()).toContain('Required proof');
  mocks.documents.mockRejectedValue({ response: { status: 403 } });
  await wrapper
    .findAll('button')
    .find(button => button.text() === 'RELATIONSHIP.REFRESH')
    .trigger('click');
  await flushPromises();
  expect(wrapper.text()).not.toContain('Required proof');
  wrapper.unmount();
});
