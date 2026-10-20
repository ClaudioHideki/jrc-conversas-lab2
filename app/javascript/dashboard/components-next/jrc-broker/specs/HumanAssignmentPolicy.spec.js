import { mount, flushPromises } from '@vue/test-utils';
import HumanAssignmentPolicy from '../HumanAssignmentPolicy.vue';
import { createJrcBrokerApi } from 'dashboard/api/jrcBroker';

vi.mock('dashboard/api/jrcBroker', () => ({ createJrcBrokerApi: vi.fn() }));

describe('Human distribution settings', () => {
  let wrapper;
  let api;
  beforeEach(() => {
    api = {
      assignmentPolicy: vi
        .fn()
        .mockResolvedValue({ enabled: false, max_open: 10, inbox_ids: [] }),
      inboxes: vi.fn().mockResolvedValue([
        { id: 7, name: 'Gopure' },
        { id: 8, name: 'Operadora' },
      ]),
      saveAssignmentPolicy: vi.fn().mockImplementation(async value => value),
    };
    createJrcBrokerApi.mockReturnValue(api);
  });
  afterEach(() => wrapper?.unmount());

  it('loads without enabling distribution and saves only an explicit valid change', async () => {
    wrapper = mount(HumanAssignmentPolicy, { props: { accountId: 1 } });
    await flushPromises();
    expect(api.saveAssignmentPolicy).not.toHaveBeenCalled();
    await wrapper.get('input[type="checkbox"]').setValue(true);
    await wrapper.get('[data-inbox-id="7"]').setValue(true);
    await wrapper.get('input[type="number"]').setValue(6);
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(api.saveAssignmentPolicy).toHaveBeenCalledWith(
      { enabled: true, max_open: 6, inbox_ids: [7] },
      expect.any(AbortSignal)
    );
  });

  it('requires an inbox selection and never selects all inboxes automatically', async () => {
    wrapper = mount(HumanAssignmentPolicy, { props: { accountId: 1 } });
    await flushPromises();
    await wrapper.get('input[type="checkbox"]').setValue(true);
    await wrapper.get('form').trigger('submit');
    expect(api.saveAssignmentPolicy).not.toHaveBeenCalled();
    expect(wrapper.get('[data-inbox-id="7"]').element.checked).toBe(false);
    expect(wrapper.get('[data-inbox-id="8"]').element.checked).toBe(false);
  });

  it('does not save invalid or partially loaded configuration', async () => {
    wrapper = mount(HumanAssignmentPolicy, { props: { accountId: 1 } });
    await flushPromises();
    await wrapper.get('input[type="number"]').setValue(0);
    await wrapper.get('form').trigger('submit');
    expect(api.saveAssignmentPolicy).not.toHaveBeenCalled();
  });

  it('does not apply a delayed response to the next account', async () => {
    let finish;
    api.assignmentPolicy.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    wrapper = mount(HumanAssignmentPolicy, { props: { accountId: 1 } });
    await wrapper.setProps({ accountId: 2 });
    await flushPromises();
    finish({ enabled: true, max_open: 99, inbox_ids: [7] });
    await flushPromises();
    expect(wrapper.get('input[type="number"]').element.value).toBe('10');
    expect(wrapper.get('input[type="checkbox"]').element.checked).toBe(false);
    expect(wrapper.get('[data-inbox-id="7"]').element.checked).toBe(false);
  });
});
