import { flushPromises, mount } from '@vue/test-utils';
import { reactive } from 'vue';
import { createI18n } from 'vue-i18n';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import TicketDetail from './TicketDetail.vue';
import { request } from './client';
import en from './en.json';

vi.mock('./client', async importOriginal => ({
  ...(await importOriginal()),
  request: vi.fn(),
}));
vi.mock('vue-router', () => ({ useRoute: vi.fn() }));
import { useRoute } from 'vue-router';

const detail = {
  ticket: {
    id: '42',
    number: '42',
    title: 'Public request',
    description: 'Description',
    status: { name: 'Open' },
    opened_at: '2026-10-25T10:00:00Z',
  },
  notes: [],
  replies: [],
  public_messages: [],
  conversations: ['10'],
  can_reply: true,
  sla: [],
  surveys: [],
};
const buildWrapper = () =>
  mount(TicketDetail, {
    global: {
      plugins: [createI18n({ legacy: false, locale: 'en', messages: { en } })],
    },
  });

describe('Requester portal native public replies', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    useRoute.mockReturnValue(reactive({ params: { id: '42' } }));
    request.mockResolvedValue(detail);
  });

  it('retries a lost reply response with the same key and blocks changed content while uncertain', async () => {
    const wrapper = buildWrapper();
    await flushPromises();
    await wrapper.get('textarea').setValue('Customer answer');
    request.mockRejectedValue(
      new TypeError('Connection interrupted after possible commit')
    );
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(request.mock.calls[1][1].headers['Idempotency-Key']).toBe(
      request.mock.calls[2][1].headers['Idempotency-Key']
    );
    await wrapper.get('textarea').setValue('Changed answer');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(request).toHaveBeenCalledTimes(3);
    expect(wrapper.get('[role="alert"]').text()).toBe(
      en.PORTAL.SUBMISSION_UNCERTAIN
    );
  });

  it('clears a confirmed reply before refreshing, even when refreshing the timeline fails', async () => {
    const wrapper = buildWrapper();
    await flushPromises();
    await wrapper.get('textarea').setValue('Customer answer');
    request.mockResolvedValueOnce({ message_id: '100' });
    request.mockRejectedValueOnce(
      new TypeError('Timeline refresh interrupted')
    );
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(wrapper.get('textarea').element.value).toBe('');
    expect(wrapper.get('[role="status"]').text()).toBe(en.PORTAL.SENT);
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(request).toHaveBeenCalledTimes(3);
  });
});
