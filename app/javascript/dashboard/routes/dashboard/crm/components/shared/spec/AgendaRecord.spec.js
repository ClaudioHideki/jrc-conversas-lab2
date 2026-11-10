import { mount, flushPromises } from '@vue/test-utils';
import { reactive } from 'vue';
import { createStore } from 'vuex';
import { activitiesAPI, followUpsAPI } from 'dashboard/api/crm';
import { useRoute } from 'vue-router';
import AgendaRecord from '../AgendaRecord.vue';

vi.mock('vue-router', () => ({ useRoute: vi.fn() }));
vi.mock('dashboard/api/crm', () => ({
  activitiesAPI: { show: vi.fn(), complete: vi.fn() },
  followUpsAPI: { show: vi.fn(), complete: vi.fn() },
}));

const render = () =>
  mount(AgendaRecord, { global: { plugins: [createStore({})] } });

it('loads and completes the original Activity without creating a copied commitment', async () => {
  useRoute.mockReturnValue(
    reactive({ params: { accountId: '1' }, query: { activityId: '9' } })
  );
  activitiesAPI.show.mockResolvedValue({
    data: { id: 9, title: 'Original meeting', status: 'scheduled' },
  });
  activitiesAPI.complete.mockResolvedValue({
    data: { id: 9, title: 'Original meeting', status: 'completed' },
  });
  const wrapper = render();
  await flushPromises();
  expect(activitiesAPI.show).toHaveBeenCalledWith('9');
  expect(wrapper.text()).toContain('Original meeting');
  await wrapper.get('[data-testid="agenda-record-complete"]').trigger('click');
  await flushPromises();
  expect(activitiesAPI.complete).toHaveBeenCalledWith('9');
  expect(wrapper.find('button').exists()).toBe(false);
  expect(wrapper.emitted('changed')).toHaveLength(1);
  wrapper.unmount();
});

it('opens editing for the original activity ID and refreshes that source after an editor save', async () => {
  useRoute.mockReturnValue(
    reactive({ params: { accountId: '1' }, query: { activityId: '9' } })
  );
  activitiesAPI.show.mockResolvedValueOnce({
    data: { id: 9, title: 'Original commitment', status: 'scheduled' },
  });
  const wrapper = render();
  await flushPromises();
  await wrapper.get('[data-testid="agenda-record-edit"]').trigger('click');
  expect(wrapper.emitted('edit')).toEqual([[9]]);
  activitiesAPI.show.mockResolvedValueOnce({
    data: { id: 9, title: 'Persisted revised commitment', status: 'scheduled' },
  });
  await wrapper.setProps({ refreshKey: 1 });
  await flushPromises();
  expect(wrapper.text()).toContain('Persisted revised commitment');
  wrapper.unmount();
});

it('clears stale content on tenant changes and uses the distinct native FollowUp endpoint', async () => {
  const route = reactive({
    params: { accountId: '1' },
    query: { followUpId: '9' },
  });
  useRoute.mockReturnValue(route);
  followUpsAPI.show.mockResolvedValueOnce({
    data: { id: 9, title: 'Original follow-up', is_completed: true },
  });
  const wrapper = render();
  await flushPromises();
  expect(followUpsAPI.show).toHaveBeenCalledWith('9');
  expect(wrapper.text()).toContain('Original follow-up');
  followUpsAPI.show.mockRejectedValueOnce(new Error('forbidden'));
  route.params.accountId = '2';
  await flushPromises();
  expect(wrapper.text()).not.toContain('Original follow-up');
  expect(wrapper.find('[role="alert"]').exists()).toBe(true);
  wrapper.unmount();
});
