import { watch } from 'vue';
import { useRoute } from 'vue-router';

// List filters are explicit at each caller. They never affect native show,
// update, selection options, or unrelated requests made by the same view.
export function useCustomerSegmentFilter() {
  const route = useRoute();
  const segmentParams = (filters = {}) => ({
    ...filters,
    ...(route.query.customer_segment_id
      ? { customer_segment_id: route.query.customer_segment_id }
      : {}),
  });
  const watchSegment = reload =>
    watch(() => route.query.customer_segment_id, reload);
  return { segmentParams, watchSegment };
}
