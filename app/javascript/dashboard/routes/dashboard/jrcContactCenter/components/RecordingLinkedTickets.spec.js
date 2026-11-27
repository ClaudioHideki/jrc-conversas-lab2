import { ref } from 'vue';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import RecordingLinkedTickets from './RecordingLinkedTickets.vue';

const mocks = vi.hoisted(() => ({ actor: null }));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => mocks.actor,
}));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) =>
      params ? `${key} ${params.number} ${params.title}` : key,
  }),
}));
vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { recordingTickets: vi.fn() },
}));
enableAutoUnmount(afterEach);
beforeEach(() => {
  vi.resetAllMocks();
  mocks.actor = ref('4');
});
const row = id => ({
  id: String(id),
  number: String(id),
  title: `SYNTHETIC Ticket ${id}`,
  status: { id: '1', name: 'SYNTHETIC pending' },
  status_phase: 'open',
});
const body = (items = [row(9)], page = 1, total = items.length) => ({
  contract_version: 1,
  account_id: '1',
  user_id: mocks.actor.value,
  recording_id: '5',
  call_session_id: '7',
  call_id: 'SYNTHETIC-call',
  items,
  meta: { page, per_page: 20, total, pages: Math.ceil(total / 20) },
});
const render = () =>
  mount(RecordingLinkedTickets, {
    props: {
      accountId: '1',
      recordingId: '5',
      callSessionId: '7',
      callId: 'SYNTHETIC-call',
      authorityKey: 'scope-1',
    },
    global: {
      stubs: {
        RouterLink: {
          name: 'RouterLink',
          props: ['to'],
          template: '<a><slot /></a>',
        },
      },
    },
  });
const button = (wrapper, suffix) =>
  wrapper.findAll('button').find(item => item.text().endsWith(suffix));

it('opens only the existing native Ticket route from a current authorized page', async () => {
  API.recordingTickets.mockResolvedValue({ data: body() });
  const wrapper = render();
  await flushPromises();
  expect(wrapper.text()).toContain('SYNTHETIC Ticket 9');
  expect(wrapper.getComponent({ name: 'RouterLink' }).props('to')).toEqual({
    name: 'jrc_service_desk_detail',
    params: { accountId: '1', ticketId: '9' },
  });
  expect(API.recordingTickets).toHaveBeenCalledWith('1', '5', 1, {
    signal: expect.any(AbortSignal),
  });
});
it('renders escaped titles and uses the actual native status without HTML injection', async () => {
  API.recordingTickets.mockResolvedValue({
    data: body([{ ...row(9), title: '<img src=x onerror=alert(1)>' }]),
  });
  const wrapper = render();
  await flushPromises();
  expect(wrapper.find('img').exists()).toBe(false);
  expect(wrapper.text()).toContain('<img src=x onerror=alert(1)>');
  expect(wrapper.text()).toContain('SYNTHETIC pending');
});
it('distinguishes an authorized empty list from a denied or failed query', async () => {
  API.recordingTickets.mockResolvedValue({ data: body([]) });
  const wrapper = render();
  await flushPromises();
  expect(wrapper.text()).toContain('LINKED_EMPTY');
  API.recordingTickets.mockRejectedValueOnce({ response: { status: 403 } });
  await button(wrapper, 'REFRESH').trigger('click');
  await flushPromises();
  expect(wrapper.text()).toContain('LINKED_DENIED');
  expect(wrapper.text()).not.toContain('LINKED_EMPTY');
});
it('retries a read error explicitly without retaining titles or pretending the count is zero', async () => {
  API.recordingTickets.mockRejectedValueOnce(
    new Error('SYNTHETIC network failure')
  );
  const wrapper = render();
  await flushPromises();
  expect(wrapper.text()).toContain('LINKED_ERROR');
  expect(wrapper.find('a').exists()).toBe(false);
  API.recordingTickets.mockResolvedValueOnce({ data: body() });
  await button(wrapper, 'REFRESH').trigger('click');
  await flushPromises();
  expect(wrapper.text()).toContain('SYNTHETIC Ticket 9');
});
it('loads the second native page and clears the previous titles while awaiting its result', async () => {
  API.recordingTickets.mockResolvedValueOnce({
    data: body(
      Array.from({ length: 20 }, (_, n) => row(n + 1)),
      1,
      21
    ),
  });
  const wrapper = render();
  await flushPromises();
  let resolve;
  API.recordingTickets.mockImplementationOnce(
    () =>
      new Promise(done => {
        resolve = done;
      })
  );
  await button(wrapper, 'NEXT').trigger('click');
  expect(wrapper.findAll('a')).toHaveLength(0);
  resolve({ data: body([row(21)], 2, 21) });
  await flushPromises();
  expect(wrapper.text()).toContain('SYNTHETIC Ticket 21');
  expect(button(wrapper, 'NEXT').attributes('disabled')).toBeDefined();
});
it('clears titles immediately after the current actor changes and ignores a late old response', async () => {
  let resolve;
  API.recordingTickets.mockImplementationOnce(
    () =>
      new Promise(done => {
        resolve = done;
      })
  );
  const wrapper = render();
  const old = body();
  API.recordingTickets.mockResolvedValueOnce({
    data: { ...body([]), user_id: '12' },
  });
  mocks.actor.value = '12';
  await flushPromises();
  resolve({ data: old });
  await flushPromises();
  expect(wrapper.text()).not.toContain('SYNTHETIC Ticket 9');
  expect(wrapper.text()).toContain('LINKED_EMPTY');
});
it('refreshes after effective authority changes even when the same recording remains selected', async () => {
  API.recordingTickets.mockResolvedValueOnce({ data: body() });
  const wrapper = render();
  await flushPromises();
  API.recordingTickets.mockRejectedValueOnce({ response: { status: 403 } });
  await wrapper.setProps({ authorityKey: 'scope-revoked' });
  expect(wrapper.findAll('a')).toHaveLength(0);
  await flushPromises();
  expect(wrapper.text()).toContain('LINKED_DENIED');
});
it.each([
  'account_id',
  'user_id',
  'recording_id',
  'call_session_id',
  'call_id',
])('rejects a response from a different %s', async key => {
  API.recordingTickets.mockResolvedValue({ data: { ...body(), [key]: '999' } });
  const wrapper = render();
  await flushPromises();
  expect(wrapper.find('a').exists()).toBe(false);
  expect(wrapper.text()).toContain('LINKED_ERROR');
});
it('rejects a duplicated native Ticket row rather than merging conflicting records', async () => {
  API.recordingTickets.mockResolvedValue({ data: body([row(9), row(9)]) });
  const wrapper = render();
  await flushPromises();
  expect(wrapper.find('a').exists()).toBe(false);
  expect(wrapper.text()).toContain('LINKED_ERROR');
});
it('aborts the owned request when the recording panel is closed', async () => {
  API.recordingTickets.mockImplementationOnce(() => new Promise(() => {}));
  const wrapper = render();
  const signal = API.recordingTickets.mock.calls[0][3].signal;
  wrapper.unmount();
  expect(signal.aborted).toBe(true);
});
