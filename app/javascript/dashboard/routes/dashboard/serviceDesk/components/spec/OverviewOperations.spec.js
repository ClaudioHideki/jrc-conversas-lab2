import { afterEach, describe, expect, it } from 'vitest';
import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import messages from 'dashboard/i18n/locale/pt_BR/jrcServiceDesk.json';
import Overview from '../OverviewOperations.vue';
let wrapper;
afterEach(() => wrapper?.unmount());
const data = {
  sla: {
    first_response_average_seconds: null,
    resolution_average_seconds: 7200,
    running_breached: 2,
  },
  evolution: [
    { date: '2026-10-01', count: 3 },
    { date: '2026-10-10', count: 4 },
    { date: '2026-10-11', count: 2 },
  ],
  top_categories: [{ id: '12', name: 'Telefonia', count: 3 }],
  by_agent: [
    {
      id: '900',
      account_user_id: '70',
      unit_id: '10',
      name: 'Operador',
      count: 4,
    },
  ],
  tasks: { open: 2, overdue: 1 },
  approvals: null,
};
const render = (props = {}) => {
  wrapper = mount(Overview, {
    props: { data, ...props },
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale: 'pt_BR',
          messages: { pt_BR: messages },
        }),
      ],
      stubs: {
        Panel: {
          template: '<section><slot name="actions" /><slot /></section>',
        },
        Button: { props: ['label'], template: '<button>{{ label }}</button>' },
      },
    },
  });
};
describe('Overview uses measured backend data', () => {
  it('separates the chart row from the summary sidebar without duplicating measured panels', () => {
    render({ section: 'summary' });
    expect(wrapper.find('svg').exists()).toBe(false);
    expect(wrapper.text()).toContain('2 h 0 min');
    expect(wrapper.text()).not.toContain('Telefonia');
  });
  it('draws category shares from the same displayed scoped counts', () => {
    render({ section: 'charts' });
    expect(wrapper.text()).toContain('Telefonia');
    expect(wrapper.text()).not.toContain('2 h 0 min');
    const arcs = wrapper.findAll('circle[pathLength="100"]');
    expect(arcs).toHaveLength(1);
    expect(arcs[0].attributes('stroke-dasharray')).toBe('100 0');
  });
  it('uses AccountUser and unit for assignee drilldown rather than membership identity', async () => {
    render();
    await wrapper
      .findAll('button')
      .find(button => button.text().includes('Operador'))
      .trigger('click');
    expect(wrapper.emitted('navigate')[0][0]).toMatchObject({
      name: 'tickets',
      query: { assignee_id: '70', unit_id: '10', phase: 'active' },
    });
  });
  it('retains date gaps in the plotted timeline and never invents missing SLA', () => {
    render();
    const circles = wrapper.findAll('circle');
    expect(Number(circles[1].attributes('cx'))).toBeGreaterThan(400);
    expect(wrapper.text()).toContain(
      messages.JRC_SERVICE_DESK.REDESIGN_LIST.not_measured
    );
    expect(wrapper.text()).toContain('2 h 0 min');
  });
});
