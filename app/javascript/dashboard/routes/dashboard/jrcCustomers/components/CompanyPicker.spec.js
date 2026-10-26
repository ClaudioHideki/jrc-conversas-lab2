import { beforeEach, afterEach, describe, it, expect, vi } from 'vitest';
import { ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
const mocks = vi.hoisted(() => ({
  companies: vi.fn(),
  company: vi.fn(),
  access: null,
}));
vi.mock('dashboard/api/jrcCustomers', () => ({ default: mocks }));
vi.mock('../useCustomerMaster', () => ({
  useCustomerMaster: () => ({ accountId: ref(1), canAccess: mocks.access }),
}));
vi.mock('vuex', () => ({
  useStore: () => ({ getters: { getCurrentUser: { id: 1 } } }),
}));
import CompanyPicker from './CompanyPicker.vue';
import { T } from '../copy';
let wrapper;
const button = label =>
  wrapper.findAll('button').find(node => node.text() === label);
beforeEach(() => {
  vi.clearAllMocks();
  mocks.access = ref(true);
});
afterEach(() => {
  wrapper?.unmount();
  vi.useRealTimers();
});
describe('Official company lookup backend pagination', () => {
  it('reaches companies after the first page even without people or tickets', async () => {
    mocks.companies.mockImplementation(({ page }) =>
      Promise.resolve({
        data: {
          payload: [
            { id: page, name: `Empresa página ${page}`, contact_count: 0 },
          ],
          meta: { total: 32 },
        },
      })
    );
    wrapper = mount(CompanyPicker);
    await button(T.search).trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain('Empresa página 1');
    await button(T.next).trigger('click');
    await flushPromises();
    expect(mocks.companies).toHaveBeenLastCalledWith({
      q: '',
      per_page: 15,
      page: 2,
    });
    expect(wrapper.text()).toContain('Empresa página 2');
  });
  it('resets pagination for a new backend query', async () => {
    vi.useFakeTimers();
    mocks.companies.mockResolvedValue({
      data: { payload: [], meta: { total: 32 } },
    });
    wrapper = mount(CompanyPicker);
    await button(T.search).trigger('click');
    await flushPromises();
    await button(T.next).trigger('click');
    await flushPromises();
    await wrapper.get('input').setValue('Nova empresa');
    await vi.advanceTimersByTimeAsync(301);
    await flushPromises();
    expect(mocks.companies).toHaveBeenLastCalledWith({
      q: 'Nova empresa',
      per_page: 15,
      page: 1,
    });
  });
  it('ignores older search responses and clears irrelevant previous results during debounce', async () => {
    vi.useFakeTimers();
    let previous;
    mocks.companies
      .mockImplementationOnce(
        () =>
          new Promise(resolve => {
            previous = resolve;
          })
      )
      .mockResolvedValueOnce({
        data: {
          payload: [{ id: 2, name: 'Empresa atual' }],
          meta: { total: 1 },
        },
      });
    wrapper = mount(CompanyPicker);
    await wrapper.get('input').setValue('Anterior');
    await vi.advanceTimersByTimeAsync(301);
    await wrapper.get('input').setValue('Atual');
    await vi.advanceTimersByTimeAsync(301);
    await flushPromises();
    previous({
      data: {
        payload: [{ id: 1, name: 'Empresa antiga' }],
        meta: { total: 1 },
      },
    });
    await flushPromises();
    expect(wrapper.text()).toContain('Empresa atual');
    expect(wrapper.text()).not.toContain('Empresa antiga');
  });
  it('does not expose companies without directory permission', () => {
    mocks.access.value = false;
    wrapper = mount(CompanyPicker);
    expect(wrapper.find('input').exists()).toBe(false);
    expect(mocks.companies).not.toHaveBeenCalled();
  });
});
