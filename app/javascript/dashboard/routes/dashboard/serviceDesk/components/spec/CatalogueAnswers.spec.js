import { beforeEach, describe, expect, it, vi } from 'vitest';
import { flushPromises, mount } from '@vue/test-utils';
import { reactive } from 'vue';
import CatalogueAnswers from '../CatalogueAnswers.vue';
const mocks = vi.hoisted(() => ({ catalogueForm: vi.fn(), session: null }));
vi.mock('dashboard/api/serviceDeskLifecycle', () => ({ default: mocks }));
vi.mock('../../composables/useServiceDesk', () => ({
  useServiceDesk: () => mocks.session,
}));
const field = {
  key: 'device',
  label: 'Device name',
  type: 'text',
  required: true,
};
const payload = (overrides = {}) => ({
  contract_version: 1,
  account_id: '1',
  unit_id: '2',
  revision: 'a'.repeat(64),
  form_fields: [field],
  service: { id: '3', name: 'Chosen service' },
  ticket_type: null,
  category: null,
  subcategory: null,
  defaults: {
    priority_id: null,
    queue_id: null,
    assignee_account_user_id: null,
  },
  allowed_company_ids: [],
  allowed_contract_ids: [],
  ...overrides,
});
const render = props =>
  mount(CatalogueAnswers, {
    props: { serviceId: '3', unitId: '2', modelValue: {}, ...props },
    global: { stubs: { ServiceDeskState: true } },
  });
beforeEach(() => {
  mocks.session = {
    state: reactive({
      status: 'ready',
      context: { account_id: '1', units: [{ id: '2' }] },
    }),
  };
  mocks.catalogueForm.mockReset().mockResolvedValue(payload());
});
describe('R3 catalogue form uses the native scoped metadata without a parallel form engine', () => {
  it('waits for the merged required fields and preserves a compatible persisted answer', async () => {
    const wrapper = render({ editing: true, modelValue: { device: 'Router' } });
    await flushPromises();
    expect(mocks.catalogueForm.mock.calls[0][1]).toEqual({
      unit_id: '2',
      service_id: '3',
      ticket_type_id: null,
      category_id: null,
      subcategory_id: null,
    });
    expect(wrapper.find('input').element.value).toBe('Router');
    expect(wrapper.emitted('ready').at(-1)).toEqual([true]);
    expect(wrapper.emitted('update:modelValue').at(-1)).toEqual([
      { device: 'Router' },
    ]);
    wrapper.unmount();
  });
  it('blocks submission until required fields are entered without inventing an answer', async () => {
    const wrapper = render();
    await flushPromises();
    expect(wrapper.emitted('ready').at(-1)).toEqual([false]);
    await wrapper.find('input').setValue('Router');
    const value = wrapper.emitted('update:modelValue').at(-1)[0];
    await wrapper.setProps({ modelValue: value });
    expect(wrapper.emitted('ready').at(-1)).toEqual([true]);
    wrapper.unmount();
  });
  it.each([
    payload({ account_id: '9' }),
    payload({ form_fields: [field, { ...field }] }),
  ])(
    'rejects duplicate schema keys and foreign Account metadata: %j',
    async response => {
      mocks.catalogueForm.mockResolvedValue(response);
      const wrapper = render();
      await flushPromises();
      expect(wrapper.findAll('input')).toHaveLength(0);
      expect(wrapper.emitted('ready').at(-1)).toEqual([false]);
      expect(wrapper.emitted('catalogue').at(-1)).toEqual([null]);
      wrapper.unmount();
    }
  );
  it('supports category/type-only forms even without a selected service', async () => {
    mocks.catalogueForm.mockResolvedValue(
      payload({ service: null, category: { id: '4', name: 'Category' } })
    );
    const wrapper = render({ serviceId: '', categoryId: '4' });
    await flushPromises();
    expect(mocks.catalogueForm.mock.calls[0][1]).toEqual({
      unit_id: '2',
      category_id: '4',
    });
    expect(wrapper.text()).toContain('Device name');
    wrapper.unmount();
  });
  it('discards stale metadata after the Account/context changes', async () => {
    let resolve;
    mocks.catalogueForm.mockReturnValue(
      new Promise(done => {
        resolve = done;
      })
    );
    const wrapper = render();
    mocks.session.state.context = { account_id: '9', units: [{ id: '2' }] };
    mocks.catalogueForm.mockResolvedValue(payload({ account_id: '9' }));
    await flushPromises();
    resolve(payload());
    await flushPromises();
    expect(
      wrapper.emitted('catalogue').filter(([value]) => value?.service).length
    ).toBe(1);
    expect(mocks.catalogueForm.mock.calls[1][0]).toBe('9');
    wrapper.unmount();
  });
});
