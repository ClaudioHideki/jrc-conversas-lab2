import { mount, flushPromises } from '@vue/test-utils';
import Versions from '../backoffice/BackofficeDocumentVersions.vue';

const api = vi.hoisted(() => ({
  documentVersions: vi.fn(),
  decideDocumentVersion: vi.fn(),
  downloadDocumentVersion: vi.fn(),
  recheckDocumentVersion: vi.fn(),
  uploadDocumentVersion: vi.fn(),
}));
vi.mock('dashboard/api/crm/commercialCycle', () => ({ backofficeAPI: api }));
const version = {
  id: 19,
  version: 2,
  current: true,
  filename: 'cadastro.pdf',
  created_at: '2026-11-01T12:00:00Z',
  status: 'review_required',
  safety: { state: 'clean', checked_at: '2026-11-01T11:59:00Z' },
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
  vi.clearAllMocks();
  api.documentVersions.mockResolvedValue({
    data: {
      requirements: [{ key: 'cnpj', label: 'Cadastro da empresa' }],
      selected_key: 'cnpj',
      data: [structuredClone(version)],
      meta: { page: 1, pages: 2, total: 6 },
    },
  });
  api.decideDocumentVersion.mockResolvedValue({ data: version });
  api.recheckDocumentVersion.mockResolvedValue({
    data: { id: 19, status: 'queued' },
  });
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

  it('keeps quarantined documents blocked and treats a queued check as pending', async () => {
    const data = (await api.documentVersions()).data;
    data.data[0].safety = { state: 'unavailable' };
    api.documentVersions.mockResolvedValue({ data });
    const wrapper = mount(Versions, {
      props: { record: { id: 7, status: 'in_progress' } },
    });
    await flushPromises();
    await wrapper
      .get('textarea')
      .setValue('Motivo humano não substitui o scanner');
    const buttons = wrapper.findAll('button');
    expect(
      buttons.find(button => button.text() === 'Aprovar').attributes('disabled')
    ).toBeDefined();
    expect(
      buttons.find(button => button.text() === 'Baixar').attributes('disabled')
    ).toBeDefined();
    await buttons
      .find(button => button.text() === 'Verificar segurança do arquivo')
      .trigger('click');
    await flushPromises();
    expect(api.recheckDocumentVersion).toHaveBeenCalledWith(7, 19);
    expect(wrapper.text()).toContain('Verificação de segurança indisponível');
    expect(wrapper.text()).not.toContain('Arquivo verificado para leitura');
    expect(api.decideDocumentVersion).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('does not create a file download after the document context is unmounted', async () => {
    let release;
    api.downloadDocumentVersion.mockReturnValueOnce(
      new Promise(resolve => {
        release = resolve;
      })
    );
    // jsdom does not provide this native browser API.
    const original = URL.createObjectURL;
    const createURL = vi.fn().mockReturnValue('blob:synthetic');
    URL.createObjectURL = createURL;
    const wrapper = mount(Versions, {
      props: { record: { id: 7, status: 'in_progress' } },
    });
    await flushPromises();
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'Baixar')
      .trigger('click');
    wrapper.unmount();
    release({ data: new Blob(['synthetic']) });
    await flushPromises();
    expect(createURL).not.toHaveBeenCalled();
    if (original) URL.createObjectURL = original;
    else delete URL.createObjectURL;
  });

  it('clears the document list if read access is denied', async () => {
    api.downloadDocumentVersion.mockRejectedValueOnce({
      response: { status: 403 },
    });
    const wrapper = mount(Versions, {
      props: { record: { id: 7, status: 'in_progress' } },
    });
    await flushPromises();
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'Baixar')
      .trigger('click');
    await flushPromises();
    expect(wrapper.text()).not.toContain('cadastro.pdf');
    expect(wrapper.emitted('changed')).toBeUndefined();
    wrapper.unmount();
  });

  it('reuses the upload intent after an uncertain response instead of creating another version', async () => {
    api.uploadDocumentVersion.mockRejectedValueOnce({
      response: { status: 503 },
    });
    api.uploadDocumentVersion.mockResolvedValueOnce({ data: version });
    const wrapper = mount(Versions, {
      props: { record: { id: 7, status: 'in_progress' } },
    });
    await flushPromises();
    const file = new File(['%PDF-synthetic'], 'synthetic.pdf', {
      type: 'application/pdf',
    });
    const input = wrapper.get('input[type="file"]');
    Object.defineProperty(input.element, 'files', { value: [file] });
    await input.trigger('change');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    const intent = api.uploadDocumentVersion.mock.calls[0][3];
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(api.uploadDocumentVersion).toHaveBeenNthCalledWith(
      2,
      7,
      'cnpj',
      file,
      intent
    );
    expect(wrapper.emitted('changed')).toHaveLength(1);
    wrapper.unmount();
  });
});
