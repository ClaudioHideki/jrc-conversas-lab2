import { mount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import RelationshipMapPanel from './RelationshipMapPanel.vue';
import API from 'dashboard/api/jrcCustomers';

const accountId = ref(1);
vi.mock('../useCustomerMaster', () => ({
  useCustomerMaster: () => ({ accountId }),
}));
vi.mock('dashboard/api/jrcCustomers', () => ({
  default: { relationships: vi.fn() },
}));

const graph = title => ({
  version: 1,
  root: { key: 'company:7' },
  sample_limit: 10,
  groups: [
    {
      kind: 'conversations',
      total: 12,
      has_more: true,
      nodes: [{ key: 'conversations:8', id: 8, display_id: 18, title }],
    },
  ],
});

describe('Customer360 relationship map', () => {
  let wrapper;
  beforeEach(() => {
    accountId.value = 1;
    API.relationships.mockResolvedValue({
      data: graph('Synthetic conversation'),
    });
    wrapper = mount(RelationshipMapPanel, {
      props: { companyId: 7, companyName: 'Synthetic customer' },
    });
  });
  afterEach(() => wrapper.unmount());

  it('loads only on demand and links a sampled group to the existing complete list', async () => {
    expect(API.relationships).not.toHaveBeenCalled();
    await wrapper.get('[data-testid="load-relationship-map"]').trigger('click');
    await flushPromises();
    expect(API.relationships).toHaveBeenCalledWith(7);
    expect(wrapper.text()).toContain('Synthetic conversation');
    expect(wrapper.text()).toContain('12');
    expect(
      wrapper.get('[data-testid="relationship-map-more"]').text()
    ).toContain('10');
    await wrapper.get('[data-kind="conversations"]').trigger('click');
    expect(wrapper.emitted('select-kind')).toEqual([['conversations']]);
  });

  it('discards a late result after switching account or customer', async () => {
    let complete;
    API.relationships.mockReturnValueOnce(
      new Promise(resolve => {
        complete = resolve;
      })
    );
    await wrapper.get('[data-testid="load-relationship-map"]').trigger('click');
    accountId.value = 2;
    await wrapper.setProps({ companyId: 9, companyName: 'New customer' });
    complete({ data: graph('OLD_ACCOUNT_CANARY') });
    await flushPromises();
    expect(wrapper.text()).not.toContain('OLD_ACCOUNT_CANARY');
    expect(wrapper.find('[data-kind="conversations"]').exists()).toBe(false);
    await wrapper.get('[data-testid="load-relationship-map"]').trigger('click');
    await flushPromises();
    expect(API.relationships).toHaveBeenLastCalledWith(9);
  });

  it('escapes record titles and supports retry after a read error', async () => {
    API.relationships.mockRejectedValueOnce({
      response: { data: { error: 'Read failed' } },
    });
    await wrapper.get('[data-testid="load-relationship-map"]').trigger('click');
    await flushPromises();
    expect(wrapper.get('[role="alert"]').text()).toContain('Read failed');
    API.relationships.mockResolvedValueOnce({
      data: graph('<img src=x onerror=alert(1)>'),
    });
    await wrapper.get('[data-testid="load-relationship-map"]').trigger('click');
    await flushPromises();
    expect(wrapper.find('img').exists()).toBe(false);
    expect(wrapper.text()).toContain('<img src=x onerror=alert(1)>');
    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
  });

  it('clears the map when only the Account changes with the same numeric customer ID', async () => {
    await wrapper.get('[data-testid="load-relationship-map"]').trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain('Synthetic conversation');
    accountId.value = 2;
    await flushPromises();
    expect(wrapper.find('[data-kind="conversations"]').exists()).toBe(false);
    expect(wrapper.props('companyId')).toBe(7);
  });
});
