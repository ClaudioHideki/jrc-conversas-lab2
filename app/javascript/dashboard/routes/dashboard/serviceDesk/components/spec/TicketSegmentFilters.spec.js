import { mount, flushPromises } from '@vue/test-utils';
import { reactive, ref } from 'vue';
import TicketFilters from '../TicketFilters.vue';

const mocks = vi.hoisted(() => ({ session: null, directory: null }));
vi.mock('../../composables/useServiceDesk', () => ({
  useServiceDesk: () => mocks.session,
}));
vi.mock('dashboard/routes/dashboard/jrcCustomers/useCustomerMaster', () => ({
  useCustomerMaster: () => ({ canAccess: mocks.directory }),
}));
const Picker = {
  name: 'SegmentTestPicker',
  props: ['modelValue', 'moduleKey'],
  emits: ['update:modelValue'],
  template: '<div />',
};
const Button = {
  name: 'SegmentTestButton',
  props: ['label', 'type'],
  template: '<button :type="type || \'button\'">{{ label }}</button>',
};
const build = query =>
  mount(TicketFilters, {
    props: { query },
    global: {
      stubs: {
        Input: true,
        Select: true,
        Button,
        ScopeBar: true,
        LookupSelect: true,
        SegmentFilterPicker: Picker,
      },
    },
  });

describe('Service Desk filters without the segment control', () => {
  beforeEach(() => {
    mocks.directory = ref(true);
    mocks.session = {
      accountId: ref('1'),
      userId: ref('2'),
      state: reactive({
        context: {
          account_id: '1',
          user_id: '2',
          units: [],
          effective_permissions: ['jrc_service_desk_customers_view'],
        },
      }),
    };
  });

  it('omits the segment picker and preserves the existing form filters', async () => {
    const wrapper = build({
      customer_segment_id: '12',
      q: 'Printer',
      phase: 'active',
    });
    expect(wrapper.findComponent(Picker).exists()).toBe(false);
    await flushPromises();
    expect(wrapper.emitted('apply')).toBeUndefined();
    await wrapper.get('form').trigger('submit');
    expect(wrapper.emitted('apply').at(-1)[0]).toMatchObject({
      customer_segment_id: '12',
      q: 'Printer',
      phase: 'active',
    });
    wrapper.unmount();
  });

  it('does not expose the removed segment section after losing directory access', async () => {
    mocks.directory.value = false;
    const wrapper = build({ customer_segment_id: '12', q: 'Printer' });
    expect(wrapper.findComponent(Picker).exists()).toBe(false);
    expect(wrapper.text()).not.toContain('Filtrar por segmento');
    expect(wrapper.text()).not.toContain('Limpar filtro de segmento');
    await wrapper.get('form').trigger('submit');
    expect(wrapper.emitted('apply').at(-1)[0]).toMatchObject({
      customer_segment_id: '12',
      q: 'Printer',
    });
    wrapper.unmount();
  });

  it('also hides the catalog without customer-data capability and synchronizes route changes', async () => {
    mocks.session.state.context.effective_permissions = [];
    const wrapper = build({});
    expect(wrapper.findComponent(Picker).exists()).toBe(false);
    mocks.session.state.context.effective_permissions = [
      'jrc_service_desk_customers_view',
    ];
    await wrapper.setProps({
      query: { customer_segment_id: '19', q: 'Updated' },
    });
    expect(wrapper.findComponent(Picker).exists()).toBe(false);
    await wrapper.get('form').trigger('submit');
    expect(wrapper.emitted('apply').at(-1)[0]).toMatchObject({
      customer_segment_id: '19',
      q: 'Updated',
    });
    wrapper.unmount();
  });
});
