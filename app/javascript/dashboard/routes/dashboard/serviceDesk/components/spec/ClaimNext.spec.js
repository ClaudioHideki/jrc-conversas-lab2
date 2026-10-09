import { describe, it, expect, beforeEach, vi } from 'vitest';
import { reactive } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import ClaimNext from '../ClaimNext.vue';
const mocks = vi.hoisted(() => ({
  session: null,
  claimNext: vi.fn(),
  ticket: vi.fn(),
  push: vi.fn(),
}));
vi.mock('dashboard/api/serviceDeskCockpit', () => ({ default: mocks }));
vi.mock('dashboard/api/serviceDeskOperations', () => ({ default: mocks }));
vi.mock('../../composables/useServiceDesk', () => ({
  useServiceDesk: () => mocks.session,
}));
vi.mock('vue-router', () => ({ useRouter: () => ({ push: mocks.push }) }));
const fresh = () => ({
  contract_version: 1,
  account_id: '1',
  ticket: {
    id: '3',
    account_id: '1',
    unit_id: '2',
    title: 'Claimed ticket',
    permissions: { show: true },
    assignee: { id: '7', name: 'Actual assignee' },
  },
});
beforeEach(() => {
  vi.clearAllMocks();
  mocks.session = reactive({
    state: {
      status: 'ready',
      context: {
        account_id: '1',
        user_id: '7',
        units: [{ id: '2', name: 'Actual unit' }],
        effective_permissions: ['jrc_service_desk_tickets_claim'],
      },
    },
    retry: vi.fn(),
  });
  mocks.claimNext.mockResolvedValue({
    applied: true,
    operation: 'claim_next',
    unit_id: '2',
    assignee_account_user_id: '7',
    account_id: '1',
    ticket_id: '3',
  });
  mocks.ticket.mockResolvedValue(fresh());
});
describe('Claim next uses an atomic native command and verified readback', () => {
  it('offers no claim control without the affirmative backend permission', async () => {
    mocks.session.state.context.effective_permissions = [];
    const wrapper = mount(ClaimNext);
    expect(wrapper.find('select').exists()).toBe(false);
    expect(mocks.claimNext).not.toHaveBeenCalled();
    wrapper.unmount();
  });
  it('requires the real unit choice and a matching independent GET before navigating', async () => {
    const wrapper = mount(ClaimNext);
    expect(wrapper.get('button').attributes('disabled')).toBeDefined();
    await wrapper.get('select').setValue('2');
    await wrapper.get('button').trigger('click');
    await flushPromises();
    expect(mocks.claimNext.mock.calls[0].slice(0, 2)).toEqual(['1', '2']);
    expect(mocks.ticket).toHaveBeenCalled();
    expect(mocks.push).toHaveBeenCalledWith({
      name: 'jrc_service_desk_detail',
      params: { accountId: '1', ticketId: '3' },
    });
    wrapper.unmount();
  });
  it('keeps the same idempotency key when a committed claim cannot yet be read back', async () => {
    mocks.ticket.mockRejectedValueOnce(new Error('GET unavailable'));
    const wrapper = mount(ClaimNext);
    await wrapper.get('select').setValue('2');
    await wrapper.get('button').trigger('click');
    await flushPromises();
    expect(mocks.push).not.toHaveBeenCalled();
    expect(wrapper.get('select').attributes('disabled')).toBeDefined();
    await wrapper.get('button').trigger('click');
    await flushPromises();
    expect(mocks.claimNext.mock.calls[0][2]).toBe(
      mocks.claimNext.mock.calls[1][2]
    );
    expect(mocks.push).toHaveBeenCalledOnce();
    wrapper.unmount();
  });
  it('does not navigate for a foreign unit projection and clears a revoked session', async () => {
    mocks.ticket.mockResolvedValue({
      ...fresh(),
      ticket: { ...fresh().ticket, unit_id: '9' },
    });
    const wrapper = mount(ClaimNext);
    await wrapper.get('select').setValue('2');
    await wrapper.get('button').trigger('click');
    await flushPromises();
    expect(mocks.push).not.toHaveBeenCalled();
    mocks.session.state.context = null;
    mocks.session.state.status = 'denied';
    await flushPromises();
    expect(wrapper.find('button').exists()).toBe(false);
    wrapper.unmount();
  });
});
