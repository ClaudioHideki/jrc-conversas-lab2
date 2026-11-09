import { describe, it, expect, vi, afterEach } from 'vitest';
import { mount, flushPromises, enableAutoUnmount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import CallObservationHistory from './CallObservationHistory.vue';
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { callObservations: vi.fn() },
}));
enableAutoUnmount(afterEach);
const props = { accountId: 1, callId: 7, allowed: true, version: 2 };
const response = (items, next = null) => ({
  data: { account_id: '1', call_session_id: 7, items, next_before_id: next },
});
describe('authorized observation revision history', () => {
  it('loads escaped revision text with a cursor and does not change the editor', async () => {
    API.callObservations.mockResolvedValueOnce(
      response(
        [
          {
            id: 3,
            call_version: 2,
            text: '<b>Nota</b>',
            created_at: '2026-11-09T12:00:00Z',
          },
        ],
        3
      )
    );
    const wrapper = mount(CallObservationHistory, { props });
    await wrapper.get('[data-observation-history-toggle]').trigger('click');
    await flushPromises();
    expect(API.callObservations).toHaveBeenLastCalledWith(1, 7, {
      limit: 20,
      before_id: null,
    });
    expect(wrapper.text()).toContain('<b>Nota</b>');
    expect(wrapper.find('b').exists()).toBe(false);
    API.callObservations.mockResolvedValueOnce(
      response([{ id: 2, call_version: 1, text: '' }])
    );
    await wrapper.get('[data-observation-history-more]').trigger('click');
    await flushPromises();
    expect(API.callObservations).toHaveBeenLastCalledWith(1, 7, {
      limit: 20,
      before_id: 3,
    });
    expect(wrapper.findAll('[data-observation-revision]')).toHaveLength(2);
    expect(wrapper.text()).toContain('VOICE_V4.NOTE_CLEARED');
  });

  it('discards a late reply after changing tenant or losing permission', async () => {
    let resolve;
    API.callObservations.mockReturnValueOnce(
      new Promise(done => {
        resolve = done;
      })
    );
    const wrapper = mount(CallObservationHistory, { props });
    await wrapper.get('[data-observation-history-toggle]').trigger('click');
    await wrapper.setProps({ accountId: 2, allowed: false });
    resolve(response([{ id: 3, text: 'Privado' }]));
    await flushPromises();
    expect(wrapper.text()).not.toContain('Privado');
    expect(wrapper.find('[data-observation-history-toggle]').exists()).toBe(
      false
    );
  });

  it('shows an error without revisions when the history API fails or returns a foreign identity', async () => {
    API.callObservations.mockRejectedValueOnce(
      new Error('synthetic network failure')
    );
    const wrapper = mount(CallObservationHistory, { props });
    await wrapper.get('[data-observation-history-toggle]').trigger('click');
    await flushPromises();
    expect(wrapper.get('[role=alert]').text()).toContain(
      'VOICE_V4.HISTORY_ERROR'
    );
    API.callObservations.mockResolvedValueOnce({
      data: {
        account_id: '2',
        call_session_id: 7,
        items: [{ id: 99, text: 'Privado' }],
      },
    });
    await wrapper.get('[data-observation-history-retry]').trigger('click');
    await flushPromises();
    expect(wrapper.text()).not.toContain('Privado');
  });
});
