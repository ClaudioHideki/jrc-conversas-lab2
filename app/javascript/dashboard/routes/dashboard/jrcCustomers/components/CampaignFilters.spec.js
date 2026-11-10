import { mount } from '@vue/test-utils';
import { ref } from 'vue';
import CampaignFilters from './CampaignFilters.vue';

const mocks = vi.hoisted(() => ({ access: null }));
vi.mock('../useCustomerMaster', () => ({
  useCustomerMaster: () => ({ canAccess: mocks.access }),
}));
const Picker = {
  name: 'CampaignSegmentPicker',
  props: ['moduleKey', 'modelValue'],
  emits: ['update:modelValue'],
  template: '<div />',
};
const render = modelValue =>
  mount(CampaignFilters, {
    props: { modelValue },
    global: { stubs: { CompanyPicker: true, SegmentFilterPicker: Picker } },
  });
beforeEach(() => {
  mocks.access = ref(true);
});

it('publishes the campaign catalog selection separately from existing company, legacy segment and department filters', () => {
  const original = {
    company_id: 2,
    segment: 'Legacy class',
    department: 'Finance',
  };
  const wrapper = render(original);
  const picker = wrapper.findComponent(Picker);
  expect(picker.props('moduleKey')).toBe('campaigns');
  picker.vm.$emit('update:modelValue', '12');
  expect(wrapper.emitted('update:modelValue')[0]).toEqual([
    { ...original, customer_segment_id: '12' },
  ]);
  expect(original).not.toHaveProperty('customer_segment_id');
  wrapper.unmount();
});

it('allows clearing a selected segment after Directory permission is lost without fetching a protected catalog', async () => {
  mocks.access = ref(false);
  const wrapper = render({
    customer_segment_id: '12',
    segment: 'Legacy class',
  });
  expect(wrapper.findComponent(Picker).exists()).toBe(false);
  await wrapper.find('button').trigger('click');
  expect(wrapper.emitted('update:modelValue')[0]).toEqual([
    { customer_segment_id: '', segment: 'Legacy class' },
  ]);
  wrapper.unmount();
});

it('hides the segment catalog when no Directory permission or selection exists', () => {
  mocks.access = ref(false);
  const wrapper = render({});
  expect(wrapper.findComponent(Picker).exists()).toBe(false);
  expect(wrapper.find('button').exists()).toBe(false);
  wrapper.unmount();
});
