import { shallowMount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import { useRoute, useRouter } from 'vue-router';
import { dealsAPI } from 'dashboard/api/crm';
import ActivitiesIndex from '../ActivitiesIndex.vue';

vi.mock('vue-router', () => ({ useRoute: vi.fn(), useRouter: vi.fn() }));
vi.mock('dashboard/api/crm', () => ({
  dealsAPI: { list: vi.fn() },
  activitiesAPI: { complete: vi.fn() },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

it('preserves semantic colors/count badges, highlights selection and applies/clears activity filters', async () => {
  useRoute.mockReturnValue({ params: { accountId: '1' }, query: {} });
  useRouter.mockReturnValue({ push: vi.fn() });
  dealsAPI.list.mockResolvedValue({ data: [] });
  const store = createStore({
    getters: {
      'jrcCrm/activities/allActivities': () => [
        {
          id: 1,
          title: 'Telefonar Maria',
          activity_type: 'call',
          user: { id: 2, name: 'Ana' },
          status: 'scheduled',
          overdue: true,
        },
        {
          id: 2,
          title: 'Visitar João',
          activity_type: 'meeting',
          user: { id: 3, name: 'Bia' },
          completed_at: '2026-09-25',
        },
      ],
    },
  });
  store.dispatch = vi.fn().mockResolvedValue();
  const wrapper = shallowMount(ActivitiesIndex, {
    global: { plugins: [store], stubs: { RouterLink: true } },
  });
  await flushPromises();
  const statusButtons = wrapper.findAll('button[aria-pressed]');
  expect(statusButtons.map(button => button.get('span').text())).toEqual([
    '1',
    '1',
    '1',
  ]);
  expect(statusButtons[0].classes()).toContain('bg-n-amber-3');
  expect(statusButtons[1].classes()).toContain('bg-n-ruby-3');
  expect(statusButtons[2].classes()).toContain('bg-n-teal-3');
  expect(
    statusButtons.every(button => button.attributes('aria-pressed') === 'false')
  ).toBe(true);
  await wrapper.get('input[type="search"]').setValue('maria');
  await wrapper.get('select[aria-label="Tipo de atividade"]').setValue('call');
  await wrapper.get('select[aria-label="Responsável"]').setValue('2');
  await statusButtons[1].trigger('click');
  expect(statusButtons[1].attributes('aria-pressed')).toBe('true');
  expect(statusButtons[1].classes()).toContain('ring-2');
  expect(wrapper.get('tbody').text()).toContain('Telefonar Maria');
  expect(wrapper.get('tbody').text()).not.toContain('Visitar João');
  await wrapper
    .findAll('button')
    .find(b => b.text() === 'Limpar filtros')
    .trigger('click');
  expect(wrapper.get('tbody').text()).toContain('Visitar João');
  expect(statusButtons[1].attributes('aria-pressed')).toBe('false');
  expect(statusButtons[1].classes()).not.toContain('ring-2');
  wrapper.unmount();
});
