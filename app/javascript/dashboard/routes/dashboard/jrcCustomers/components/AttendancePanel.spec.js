import { computed, reactive } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import { beforeEach, expect, it, vi } from 'vitest';
import { createI18n } from 'vue-i18n';
import messages from 'dashboard/i18n/locale/en/crm.json';
import Panel from './AttendancePanel.vue';
const mocks = vi.hoisted(() => ({ state: null, attendance: vi.fn() }));
vi.mock('dashboard/api/jrcCustomers', () => ({ default: mocks }));
vi.mock('../useCustomerMaster', () => ({
  useCustomerMaster: () => ({
    identity: computed(() => JSON.stringify(mocks.state)),
    accountId: computed(() => mocks.state.account),
  }),
}));
const data = () => ({
  period: {
    from: '2026-11-01',
    to: '2026-11-02',
    timezone: 'America/Sao_Paulo',
  },
  channels: ['Channel::Email'],
  conversations: {
    created: 7,
    current_statuses: { open: 2 },
    by_channel: { 'Channel::Email': 7 },
  },
  messages: { incoming: 12, outgoing: 6 },
  csat: { available: true, responses: 0, satisfied_percent: null },
  conversation_sla: { available: false },
  ticket_sla: { available: false },
});
const render = (props = { companyId: 80 }) =>
  mount(Panel, {
    props,
    global: {
      plugins: [
        createI18n({ legacy: false, locale: 'en', messages: { en: messages } }),
      ],
    },
  });
beforeEach(() => {
  mocks.state = reactive({ account: '1', role: 'admin' });
  mocks.attendance.mockReset().mockResolvedValue({ data: data() });
});
it('loads only after the user opens the panel and distinguishes unavailable sources from zero replies', async () => {
  const wrapper = render();
  expect(mocks.attendance).not.toHaveBeenCalled();
  await wrapper.get('button').trigger('click');
  await flushPromises();
  expect(wrapper.text()).toContain('Sem respostas');
  expect(wrapper.text()).toContain('Indisponível');
  expect(wrapper.text()).not.toContain('100%');
  expect(mocks.attendance).toHaveBeenCalledWith(
    'companies',
    80,
    expect.any(Object),
    expect.objectContaining({ accountId: '1' })
  );
  wrapper.unmount();
});
it('applies explicit dates/channel and clears filters through a fresh server query', async () => {
  const wrapper = render({ contactId: 33 });
  await wrapper.get('button').trigger('click');
  await flushPromises();
  await wrapper.findAll('input')[0].setValue('2026-10-01');
  await wrapper.findAll('input')[1].setValue('2026-10-31');
  await wrapper.get('select').setValue('Channel::Email');
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  expect(mocks.attendance.mock.calls.at(-1)).toEqual([
    'contacts',
    33,
    { from: '2026-10-01', to: '2026-10-31', channel: 'Channel::Email' },
    expect.objectContaining({
      accountId: '1',
      signal: expect.any(AbortSignal),
    }),
  ]);
  await wrapper
    .findAll('button')
    .find(row => row.text() === 'Limpar filtros')
    .trigger('click');
  await flushPromises();
  expect(mocks.attendance.mock.calls.at(-1)[2]).toEqual({
    from: undefined,
    to: undefined,
    channel: undefined,
  });
  wrapper.unmount();
});
it('clears old values after an access denial instead of retaining stale indicators', async () => {
  const wrapper = render();
  await wrapper.get('button').trigger('click');
  await flushPromises();
  mocks.attendance.mockRejectedValue({ response: { status: 403 } });
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  expect(wrapper.find('dl').exists()).toBe(false);
  expect(wrapper.find('[role="alert"]').exists()).toBe(true);
  wrapper.unmount();
});
it('does not show a response from the previous account/role even when abort is ignored', async () => {
  let finish;
  mocks.attendance.mockImplementation(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  const wrapper = render();
  await wrapper.get('button').trigger('click');
  mocks.state.account = '2';
  await flushPromises();
  finish({ data: data() });
  await flushPromises();
  expect(wrapper.find('dl').exists()).toBe(false);
  expect(wrapper.get('button').attributes('aria-expanded')).toBe('false');
  wrapper.unmount();
});
