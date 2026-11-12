import { defineComponent } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import Editor from '../backoffice/ContractDraftEditor.vue';
import Details from '../backoffice/ContractVersionDetails.vue';

const api = vi.hoisted(() => ({
  draft: vi.fn(),
  updateDraft: vi.fn(),
  download: vi.fn(),
  differences: vi.fn(),
  templates: vi.fn(),
}));
vi.mock('dashboard/api/crm/commercialCycle', () => ({
  backofficeContractVersionsAPI: api,
}));
const DialogStub = defineComponent({
  setup(_, { expose }) {
    expose({ open: vi.fn(), close: vi.fn() });
  },
  template: '<div><slot /></div>',
});
const mountGlobals = { stubs: { Dialog: DialogStub } };
const draft = {
  id: 7,
  template: { name: 'Modelo jurídico sintético' },
  content_override: 'Minuta autorizada',
  notes: '',
  starts_on: '2026-11-02',
  ends_on: '2027-11-02',
  source_digest: 'b'.repeat(64),
  signature_status: 'prepared',
};
const editorProps = { accountId: '1', requestId: 9 };
const version = {
  id: 19,
  number: 2,
  change_reason: 'Revisão',
  pdf_sha256: 'a'.repeat(64),
};
const originalCreate = URL.createObjectURL;
const originalRevoke = URL.revokeObjectURL;
beforeAll(() => {
  URL.createObjectURL = vi.fn(() => 'blob:synthetic-contract');
  URL.revokeObjectURL = vi.fn();
});
afterAll(() => {
  URL.createObjectURL = originalCreate;
  URL.revokeObjectURL = originalRevoke;
});
beforeEach(() => {
  api.templates.mockResolvedValue({
    data: { data: [], meta: { page: 1, pages: 1, total: 0 } },
  });
  api.draft.mockResolvedValue({ data: structuredClone(draft) });
  api.updateDraft.mockResolvedValue({ data: { id: 7 } });
  api.download.mockResolvedValue({
    data: new Blob(['%PDF-synthetic-viewer-unit-test'], {
      type: 'application/pdf',
    }),
  });
  api.differences.mockResolvedValue({
    data: {
      data: [
        {
          path: 'contract.content_override',
          before: 'Texto anterior',
          after: 'Texto revisado',
        },
      ],
    },
  });
});

describe('Contextual contract draft editing', () => {
  it('selects a native template without erasing a typed draft until the user explicitly chooses its text', async () => {
    const wrapper = mount(Editor, {
      props: editorProps,
      global: {
        stubs: { ...mountGlobals.stubs, ContractTemplatePicker: true },
      },
    });
    await flushPromises();
    await wrapper
      .findAll('button')
      .find(item => item.text() === 'Selecionar modelo contratual')
      .trigger('click');
    wrapper
      .findComponent({ name: 'ContractTemplatePicker' })
      .vm.$emit('choose', {
        id: 82,
        name: 'TESTE SINTÉTICO — Modelo escolhido',
      });
    await flushPromises();
    expect(wrapper.get('textarea[name="contract_draft"]').element.value).toBe(
      'Minuta autorizada'
    );
    expect(wrapper.text()).toContain('TESTE SINTÉTICO — Modelo escolhido');
    await wrapper
      .findAll('button')
      .find(item => item.text() === 'Usar texto do modelo selecionado')
      .trigger('click');
    expect(wrapper.get('textarea[name="contract_draft"]').element.value).toBe(
      ''
    );
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(api.updateDraft).toHaveBeenCalledWith(
      '1',
      9,
      expect.objectContaining({
        contract_template_id: 82,
        content_override: '',
      }),
      'b'.repeat(64),
      expect.objectContaining({ signal: expect.any(AbortSignal) })
    );
    wrapper.unmount();
  });

  it('clears the form when access to contextual models is withdrawn and supports explicit removal of the model', async () => {
    api.draft.mockResolvedValueOnce({
      data: {
        ...structuredClone(draft),
        template: { id: 81, name: 'Modelo sintético atual' },
      },
    });
    const wrapper = mount(Editor, {
      props: editorProps,
      global: {
        stubs: { ...mountGlobals.stubs, ContractTemplatePicker: true },
      },
    });
    await flushPromises();
    await wrapper
      .findAll('button')
      .find(item => item.text() === 'Usar somente minuta própria')
      .trigger('click');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(api.updateDraft.mock.calls[0][2]).toEqual(
      expect.objectContaining({
        contract_template_id: null,
        content_override: 'Minuta autorizada',
      })
    );
    await wrapper
      .findAll('button')
      .find(item => item.text() === 'Selecionar modelo contratual')
      .trigger('click');
    wrapper
      .findComponent({ name: 'ContractTemplatePicker' })
      .vm.$emit('denied');
    await flushPromises();
    expect(wrapper.find('textarea').exists()).toBe(false);
    expect(wrapper.emitted('denied')).toHaveLength(1);
    wrapper.unmount();
  });
  it('loads the native template and sends only editable fields with the original digest', async () => {
    const wrapper = mount(Editor, { props: editorProps, global: mountGlobals });
    await flushPromises();
    expect(wrapper.text()).toContain('Modelo jurídico sintético');
    await wrapper
      .get('textarea[name="contract_draft"]')
      .setValue('Minuta revisada pela pessoa autorizada');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(api.updateDraft).toHaveBeenCalledWith(
      '1',
      9,
      {
        content_override: 'Minuta revisada pela pessoa autorizada',
        notes: '',
        starts_on: '2026-11-02',
        ends_on: '2027-11-02',
      },
      'b'.repeat(64),
      expect.objectContaining({ signal: expect.any(AbortSignal) })
    );
    expect(wrapper.emitted('saved')).toHaveLength(1);
    wrapper.unmount();
  });

  it('does not claim a save without an acknowledgement and holds a stale draft after conflict', async () => {
    api.updateDraft.mockResolvedValueOnce({ data: {} });
    const wrapper = mount(Editor, { props: editorProps, global: mountGlobals });
    await flushPromises();
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(wrapper.emitted('saved')).toBeUndefined();
    api.updateDraft.mockRejectedValueOnce({
      response: { status: 409, data: { code: 'CONTRACT_SOURCE_CHANGED' } },
    });
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(wrapper.text()).toContain('A minuta mudou desde a prévia');
    expect(
      wrapper.get('button[type="submit"]').attributes('disabled')
    ).toBeDefined();
    expect(wrapper.emitted('saved')).toBeUndefined();
    wrapper.unmount();
  });

  it('clears denied data and keeps sent or signed documents read only', async () => {
    api.draft.mockRejectedValueOnce({ response: { status: 403 } });
    const denied = mount(Editor, { props: editorProps, global: mountGlobals });
    await flushPromises();
    expect(denied.emitted('denied')).toHaveLength(1);
    expect(denied.find('textarea').exists()).toBe(false);
    denied.unmount();
    api.draft.mockResolvedValue({
      data: { ...draft, signature_status: 'sent' },
    });
    const locked = mount(Editor, { props: editorProps, global: mountGlobals });
    await flushPromises();
    expect(
      locked.get('textarea[name="contract_draft"]').attributes('disabled')
    ).toBeDefined();
    expect(
      locked.get('button[type="submit"]').attributes('disabled')
    ).toBeDefined();
    expect(api.updateDraft).not.toHaveBeenCalled();
    locked.unmount();
  });

  it('ignores an acknowledgement delivered after the editor was closed', async () => {
    let release;
    api.updateDraft.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          release = resolve;
        })
    );
    const wrapper = mount(Editor, { props: editorProps, global: mountGlobals });
    await flushPromises();
    await wrapper.get('form').trigger('submit');
    wrapper.unmount();
    release({ data: { id: 7 } });
    await flushPromises();
    expect(wrapper.emitted('saved')).toBeUndefined();
  });
});

describe('Protected contract revision reading', () => {
  it('loads the scoped PDF and revokes the local object URL on close', async () => {
    const wrapper = mount(Details, {
      props: { ...editorProps, version, mode: 'pdf' },
      global: mountGlobals,
    });
    await flushPromises();
    expect(api.download).toHaveBeenCalledWith(
      '1',
      9,
      19,
      expect.objectContaining({ signal: expect.any(AbortSignal) })
    );
    expect(wrapper.get('iframe').attributes('src')).toBe(
      'blob:synthetic-contract'
    );
    wrapper.unmount();
    expect(URL.revokeObjectURL).toHaveBeenCalledWith('blob:synthetic-contract');
  });

  it('does not open a file returned after its context was unmounted', async () => {
    let release;
    api.download.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          release = resolve;
        })
    );
    const wrapper = mount(Details, {
      props: { ...editorProps, version, mode: 'pdf' },
      global: mountGlobals,
    });
    wrapper.unmount();
    release({ data: new Blob(['%PDF-synthetic-late-test']) });
    await flushPromises();
    expect(URL.createObjectURL).not.toHaveBeenCalled();
  });

  it('shows actual differences as text and signals denied evidence access', async () => {
    const wrapper = mount(Details, {
      props: { ...editorProps, version, mode: 'differences' },
      global: mountGlobals,
    });
    await flushPromises();
    expect(wrapper.text()).toContain('Texto anterior');
    expect(wrapper.text()).toContain('Texto revisado');
    expect(wrapper.text()).toContain('Minuta contratual');
    wrapper.unmount();
    api.download.mockRejectedValueOnce({ response: { status: 403 } });
    const denied = mount(Details, {
      props: { ...editorProps, version, mode: 'pdf' },
      global: mountGlobals,
    });
    await flushPromises();
    expect(denied.emitted('denied')).toHaveLength(1);
    expect(denied.find('iframe').exists()).toBe(false);
    denied.unmount();
  });
});
