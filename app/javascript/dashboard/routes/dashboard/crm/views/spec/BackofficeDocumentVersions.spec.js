import { mount, flushPromises } from '@vue/test-utils';
import Versions from '../backoffice/BackofficeDocumentVersions.vue';

const api = vi.hoisted(() => ({
  documentVersions: vi.fn(),
  decideDocumentVersion: vi.fn(),
}));
vi.mock('dashboard/api/crm/commercialCycle', () => ({ backofficeAPI: api }));
const version = {
  id: 19,
  version: 2,
  current: true,
  filename: 'cadastro.pdf',
  created_at: '2026-11-01T12:00:00Z',
  status: 'review_required',
  decisions: [],
  analysis: {
    analyzer_version: 'local-document-checks/1',
    created_at: '2026-11-01T12:00:00Z',
    evidence: {
      engine: 'poppler',
      page_limit: 5,
      checks: { customer_identifier: 'mismatch' },
    },
  },
};
beforeEach(() => {
  api.documentVersions.mockResolvedValue({
    data: {
      requirements: [{ key: 'cnpj', label: 'Cadastro da empresa' }],
      selected_key: 'cnpj',
      data: [structuredClone(version)],
      meta: { page: 1, pages: 2, total: 6 },
    },
  });
  api.decideDocumentVersion.mockResolvedValue({ data: version });
});
describe('Backoffice documentary review', () => {
  it('requires a reason for a human decision and sends the current version identifier', async () => {
    const wrapper = mount(Versions, {
      props: { record: { id: 7, status: 'in_progress' } },
    });
    await flushPromises();
    expect(wrapper.text()).toContain('Divergente');
    const approve = () =>
      wrapper.findAll('button').find(button => button.text() === 'Aprovar');
    expect(approve().attributes('disabled')).toBeDefined();
    await wrapper
      .get('textarea')
      .setValue('Conferido com o cadastro e evidência original');
    await approve().trigger('click');
    await flushPromises();
    expect(api.decideDocumentVersion).toHaveBeenCalledWith(7, 19, {
      status: 'approved',
      reason: 'Conferido com o cadastro e evidência original',
    });
    expect(wrapper.emitted('changed')).toHaveLength(1);
    wrapper.unmount();
  });
  it('keeps superseded versions readable without decision controls and requests server pagination', async () => {
    api.documentVersions.mockResolvedValue({
      data: {
        requirements: [{ key: 'cnpj', label: 'Cadastro da empresa' }],
        selected_key: 'cnpj',
        data: [{ ...version, current: false }],
        meta: { page: 1, pages: 2, total: 6 },
      },
    });
    const wrapper = mount(Versions, {
      props: { record: { id: 7, status: 'in_progress' } },
    });
    await flushPromises();
    expect(
      wrapper.findAll('button').some(button => button.text() === 'Aprovar')
    ).toBe(false);
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'Histórico de versões')
      .trigger('click');
    await flushPromises();
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'Próxima')
      .trigger('click');
    await flushPromises();
    expect(api.documentVersions).toHaveBeenLastCalledWith(7, {
      document_key: 'cnpj',
      page: 2,
    });
    wrapper.unmount();
  });
  it('disables new uploads and decisions after completion', async () => {
    const wrapper = mount(Versions, {
      props: { record: { id: 7, status: 'completed' } },
    });
    await flushPromises();
    expect(
      wrapper.get('input[type="file"]').attributes('disabled')
    ).toBeDefined();
    expect(
      wrapper.findAll('button').some(button => button.text() === 'Aprovar')
    ).toBe(false);
    wrapper.unmount();
  });
});
