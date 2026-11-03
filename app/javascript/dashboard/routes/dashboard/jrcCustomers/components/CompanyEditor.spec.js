import { mount, flushPromises } from '@vue/test-utils';
import Editor from './CompanyEditor.vue';

const mocks = vi.hoisted(() => ({ metadata: vi.fn(), saveCompany: vi.fn() }));
vi.mock('dashboard/api/jrcCustomers', () => ({ default: mocks }));
const record = {
  id: 101,
  name: 'MOCK — Empresa',
  email: 'empresa@example.test',
  economic_group: 'MOCK — Grupo',
  parent_company_id: 102,
  relationship_type: 'customer',
  relationship_tags: ['partner'],
  revision: '2026-11-02T12:00:00Z',
};
const render = (company = record) =>
  mount(Editor, {
    props: { company },
    attachTo: document.body,
    global: { stubs: { CompanyPicker: true } },
  });
beforeEach(() => {
  vi.clearAllMocks();
  mocks.metadata.mockResolvedValue({
    data: { owners: [], segments: ['MOCK — Segmento'] },
  });
  mocks.saveCompany.mockResolvedValue({
    data: { payload: { ...record, name: 'MOCK — Alterada' } },
  });
});

it('retains values in every tab and submits the exact native revision and relationships', async () => {
  const wrapper = render();
  await flushPromises();
  await wrapper
    .find('fieldset[data-section="identity"] input')
    .setValue('MOCK — Alterada');
  await wrapper.findAll('nav button')[1].trigger('click');
  await wrapper.find('input[type="email"]').setValue('nova@example.test');
  await wrapper.findAll('nav button')[3].trigger('click');
  expect(wrapper.find('fieldset[data-section="structure"]').isVisible()).toBe(
    true
  );
  await wrapper
    .find('fieldset[data-section="structure"] input')
    .setValue('MOCK — Novo grupo');
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  expect(mocks.saveCompany).toHaveBeenCalledWith(
    expect.objectContaining({
      name: 'MOCK — Alterada',
      email: 'nova@example.test',
      economic_group: 'MOCK — Novo grupo',
      parent_company_id: 102,
      relationship_type: 'customer',
      relationship_tags: ['partner'],
      revision: record.revision,
    }),
    101
  );
  expect(wrapper.emitted('saved')[0][0].id).toBe(101);
  wrapper.unmount();
});

it('opens the tab containing a native invalid field before attempting a write', async () => {
  const wrapper = render(null);
  await flushPromises();
  await wrapper.findAll('nav button')[3].trigger('click');
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  expect(mocks.saveCompany).not.toHaveBeenCalled();
  expect(wrapper.find('fieldset[data-section="identity"]').isVisible()).toBe(
    true
  );
  expect(document.activeElement).toBe(wrapper.find('input[required]').element);
  await wrapper.find('input[required]').setValue('MOCK — Nova empresa');
  await wrapper.findAll('nav button')[1].trigger('click');
  await wrapper.find('input[type="email"]').setValue('invalid-email');
  await wrapper.findAll('nav button')[2].trigger('click');
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  expect(mocks.saveCompany).not.toHaveBeenCalled();
  expect(
    wrapper.find('fieldset[data-section="communication"]').isVisible()
  ).toBe(true);
  expect(document.activeElement).toBe(
    wrapper.find('input[type="email"]').element
  );
  wrapper.unmount();
});

it('preserves the draft and revision after a server conflict without claiming success', async () => {
  mocks.saveCompany.mockRejectedValue({
    response: {
      status: 409,
      data: { error: 'MOCK — cadastro alterado por outra pessoa' },
    },
  });
  const wrapper = render();
  await flushPromises();
  await wrapper.find('input[required]').setValue('MOCK — Rascunho');
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  expect(wrapper.find('[role="alert"]').text()).toContain(
    'MOCK — cadastro alterado'
  );
  expect(wrapper.find('input[required]').element.value).toBe('MOCK — Rascunho');
  expect(wrapper.emitted('saved')).toBeUndefined();
  expect(wrapper.find('button[type="submit"]').element.disabled).toBe(false);
  wrapper.unmount();
});
