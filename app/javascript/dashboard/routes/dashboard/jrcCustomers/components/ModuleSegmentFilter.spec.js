import { computed, reactive } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import Filter from './ModuleSegmentFilter.vue';

const mocks = vi.hoisted(() => ({
  route: null,
  allowed: null,
  replace: vi.fn(),
}));
vi.mock('vue-router', () => ({
  useRoute: () => mocks.route,
  useRouter: () => ({ replace: mocks.replace }),
}));
vi.mock('../useCustomerMaster', () => ({
  useCustomerMaster: () => ({ canAccess: computed(() => mocks.allowed.value) }),
}));

it('preserves native query filters while applying or clearing the module segment and hides without directory permission', async () => {
  mocks.route = reactive({
    query: { customer_segment_id: '7', page: '2', status: 'open' },
  });
  mocks.allowed = reactive({ value: true });
  const wrapper = mount(Filter, {
    props: { moduleKey: 'crm' },
    global: { stubs: { SegmentFilterPicker: true } },
  });
  const picker = wrapper.getComponent({ name: 'SegmentFilterPicker' });
  expect(picker.props('moduleKey')).toBe('crm');
  picker.vm.$emit('update:modelValue', 8);
  expect(mocks.replace).toHaveBeenLastCalledWith({
    query: { customer_segment_id: '8', status: 'open' },
  });
  picker.vm.$emit('update:modelValue', '');
  expect(mocks.replace).toHaveBeenLastCalledWith({ query: { status: 'open' } });
  mocks.allowed.value = false;
  await flushPromises();
  expect(wrapper.findComponent({ name: 'SegmentFilterPicker' }).exists()).toBe(
    false
  );
  await wrapper.get('button').trigger('click');
  expect(mocks.replace).toHaveBeenLastCalledWith({ query: { status: 'open' } });
  delete mocks.route.query.customer_segment_id;
  await flushPromises();
  expect(wrapper.find('section').exists()).toBe(false);
  wrapper.unmount();
});
