import { defineComponent, reactive } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import { useCustomerSegmentFilter } from './useCustomerSegmentFilter';

const mocks = vi.hoisted(() => ({ route: null }));
vi.mock('vue-router', () => ({ useRoute: () => mocks.route }));

it('merges only the explicit list parameter and reloads after browser query navigation', async () => {
  mocks.route = reactive({
    query: { customer_segment_id: '9', user_id: 'forged' },
  });
  const reload = vi.fn();
  let params;
  const wrapper = mount(
    defineComponent({
      setup() {
        const filter = useCustomerSegmentFilter();
        params = filter.segmentParams;
        filter.watchSegment(reload);
        return () => null;
      },
    })
  );
  expect(params({ status: 'open' })).toEqual({
    status: 'open',
    customer_segment_id: '9',
  });
  mocks.route.query.customer_segment_id = '10';
  await flushPromises();
  expect(reload).toHaveBeenCalledTimes(1);
  delete mocks.route.query.customer_segment_id;
  await flushPromises();
  expect(params({ status: 'open' })).toEqual({ status: 'open' });
  expect(reload).toHaveBeenCalledTimes(2);
  wrapper.unmount();
});
