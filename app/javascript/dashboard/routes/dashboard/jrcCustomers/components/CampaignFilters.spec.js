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

it('removes the segment picker while preserving company and classification filters', () => {
  const original = {
    company_id: 2,
    segment: 'Legacy class',
    department: 'Finance',
  };
  const wrapper = render(original);
  expect(wrapper.findComponent(Picker).exists()).toBe(false);
  wrapper
    .findComponent({ name: 'CompanyPicker' })
    .vm.$emit('update:modelValue', 3);
  expect(wrapper.emitted('update:modelValue')[0]).toEqual([
    { ...original, company_id: 3 },
  ]);
  expect(original).not.toHaveProperty('customer_segment_id');
  wrapper.unmount();
});

it('does not expose the removed segment control or alter an existing campaign audience', async () => {
  mocks.access = ref(false);
  const wrapper = render({
    customer_segment_id: '12',
    segment: 'Legacy class',
  });
  expect(wrapper.findComponent(Picker).exists()).toBe(false);
  expect(wrapper.find('button').exists()).toBe(false);
  expect(wrapper.emitted('update:modelValue')).toBeUndefined();
  wrapper.unmount();
});

it('hides the segment catalog when no Directory permission or selection exists', () => {
  mocks.access = ref(false);
  const wrapper = render({});
  expect(wrapper.findComponent(Picker).exists()).toBe(false);
  expect(wrapper.find('button').exists()).toBe(false);
  wrapper.unmount();
});
