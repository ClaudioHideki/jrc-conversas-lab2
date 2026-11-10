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

describe('Service Desk published customer segment control', () => {
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

  it('uses the Service Desk catalog and applies the selected segment with the existing form filters', async () => {
    const wrapper = build({
      customer_segment_id: '12',
      q: 'Printer',
      phase: 'active',
    });
    const picker = wrapper.getComponent(Picker);
    expect(picker.props('moduleKey')).toBe('service_desk');
    expect(picker.props('modelValue')).toBe('12');
    picker.vm.$emit('update:modelValue', '13');
    await flushPromises();
    expect(wrapper.emitted('apply')).toBeUndefined();
    await wrapper.get('form').trigger('submit');
    expect(wrapper.emitted('apply').at(-1)[0]).toMatchObject({
      customer_segment_id: '13',
      q: 'Printer',
      phase: 'active',
    });
    wrapper.unmount();
  });

  it('can remove a segment after losing directory access without loading the protected catalog or clearing other filters', async () => {
    mocks.directory.value = false;
    const wrapper = build({ customer_segment_id: '12', q: 'Printer' });
    expect(wrapper.findComponent(Picker).exists()).toBe(false);
    await wrapper
      .findAllComponents(Button)
      .find(button => button.props('label') === 'Limpar filtro de segmento')
      .trigger('click');
    expect(wrapper.emitted('apply').at(-1)[0]).toMatchObject({
      customer_segment_id: '',
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
    expect(wrapper.getComponent(Picker).props('modelValue')).toBe('19');
    await wrapper.get('form').trigger('submit');
    expect(wrapper.emitted('apply').at(-1)[0]).toMatchObject({
      customer_segment_id: '19',
      q: 'Updated',
    });
    wrapper.unmount();
  });
});
