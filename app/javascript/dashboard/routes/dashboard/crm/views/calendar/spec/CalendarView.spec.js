import { shallowMount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import { useRoute } from 'vue-router';
import { activitiesAPI } from 'dashboard/api/crm';
import CalendarView from '../CalendarView.vue';

vi.mock('vue-router', () => ({ useRoute: vi.fn() }));
vi.mock('dashboard/api/crm', () => ({
  activitiesAPI: { complete: vi.fn() },
}));

it('explains unsupported calendar controls while preserving the weekly view and completion', async () => {
  useRoute.mockReturnValue({
    params: { accountId: '1' },
    query: { date: '2026-09-30' },
  });
  activitiesAPI.complete.mockResolvedValue({});
  const store = createStore({
    getters: {
      'jrcCrm/activities/allActivities': () => [
        {
          id: 1,
          title: 'Reunião de teste',
          due_at: '2026-09-30T12:00:00Z',
          activity_type: 'meeting',
        },
      ],
    },
  });
  store.dispatch = vi.fn().mockResolvedValue();
  const wrapper = shallowMount(CalendarView, {
    global: {
      plugins: [store],
      stubs: { RouterLink: true, CrmPageHeader: false },
    },
  });
  await flushPromises();

  const unavailableButtons = wrapper.findAll('button[aria-describedby]');
  expect(unavailableButtons.map(button => button.text())).toEqual([
    'Sincronizar calendário',
    'Mês',
    'Dia',
    'Lista',
    'Iniciar ligação',
    'WhatsApp',
    'Reagendar',
  ]);
  await Promise.all(
    unavailableButtons.map(async button => {
      expect(button.element.disabled).toBe(true);
      const explanation = wrapper.get(
        `#${button.attributes('aria-describedby')}`
      );
      expect(explanation.isVisible()).toBe(true);
      expect(explanation.text()).toMatch(/indisponível|não est/);
      await button.trigger('click');
    })
  );
  const filters = wrapper.findAll('input[type="checkbox"]');
  expect(filters).toHaveLength(6);
  expect(filters.every(input => input.element.disabled)).toBe(true);
  expect(filters.every(input => !input.element.checked)).toBe(true);
  expect(wrapper.get('#crm-calendar-filter-note').text()).toContain(
    'não estão disponíveis'
  );
  expect(wrapper.get('[aria-current="true"]').text()).toBe('Semana');
  expect(wrapper.get('article').text()).toContain('Reunião de teste');
  expect(store.dispatch).toHaveBeenCalledTimes(1);
  expect(activitiesAPI.complete).not.toHaveBeenCalled();

  await wrapper.get('article button').trigger('click');
  await flushPromises();
  expect(activitiesAPI.complete).toHaveBeenCalledWith(1);
  expect(store.dispatch).toHaveBeenCalledTimes(2);
  wrapper.unmount();
});
