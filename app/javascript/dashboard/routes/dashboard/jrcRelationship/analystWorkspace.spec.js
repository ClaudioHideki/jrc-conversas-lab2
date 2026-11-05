import { reactive } from 'vue';
import { shallowMount, flushPromises } from '@vue/test-utils';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import AnalystWorkspace from './AnalystWorkspace.vue';
import ActionCasePanel from './ActionCasePanel.vue';
import { AREAS, areaForScreen, visibleAreas } from './navigation';
import { SCREENS } from './definitions';
const mocks = vi.hoisted(() => ({
  route: null,
  store: null,
  replace: vi.fn(),
  api: {
    metadata: vi.fn(),
    dashboard: vi.fn(),
    records: vi.fn(),
    record: vi.fn(),
    channels: vi.fn(),
    saveRecord: vi.fn(),
  },
}));
vi.mock('vue-router', () => ({
  useRoute: () => mocks.route,
  useRouter: () => ({ replace: mocks.replace }),
}));
vi.mock('vuex', async original => ({
  ...(await original()),
  useStore: () => mocks.store,
}));
vi.mock('dashboard/api/jrcRelationship', () => ({ default: mocks.api }));
const metadata = {
  can_manage: true,
  can_team: false,
  can_configure: false,
  formatting: {},
};
beforeEach(() => {
  vi.clearAllMocks();
  mocks.route = reactive({
    params: { accountId: '1' },
    query: { q: 'Synthetic', page: '2' },
  });
  mocks.store = { getters: reactive({ getCurrentUserID: 7 }) };
  mocks.api.metadata.mockResolvedValue({ data: metadata });
  mocks.api.records.mockResolvedValue({
    data: { payload: [], meta: { page: 2, total: 30, per_page: 25 } },
  });
  mocks.api.dashboard.mockResolvedValue({
    data: { priority_actions: [], customers: 0, at_risk: null },
  });
  mocks.api.record.mockResolvedValue({
    data: {
      id: 5,
      assignment_id: 19,
      customer_name: 'Synthetic',
      status: 'in_progress',
      lock_version: 2,
      source_links: [],
    },
  });
  mocks.api.channels.mockResolvedValue({ data: { channel_conversations: [] } });
});
describe('Relationship V2 analyst workflow', () => {
  it('shows real pending routing without pretending a critical case has an owner and keeps native follow-up available', async () => {
    mocks.api.record.mockResolvedValue({
      data: {
        id: 5,
        assignment_id: 19,
        owner_id: null,
        status: 'open',
        priority: 95,
        customer_confirmation: 'not_applicable',
        metadata: { routing_waiting_reason: 'no_authorized_available_analyst' },
        factors: {
          trend: { normalized: 25, weight: 0.25 },
          sla: { normalized: 100, weight: 0.5 },
        },
      },
    });
    const wrapper = shallowMount(ActionCasePanel, {
      props: { actionId: 5, metadata },
    });
    await flushPromises();
    expect(
      wrapper.get('[data-testid="routing-waiting"]').attributes('role')
    ).toBe('status');
    expect(
      wrapper.get('[data-testid="priority-factor-trend"]').text()
    ).toContain('25');
    expect(wrapper.get('[data-testid="priority-factor-sla"]').text()).toContain(
      '100'
    );
    expect(wrapper.find('[data-testid="record-follow-up"]').exists()).toBe(
      true
    );
    mocks.api.record.mockResolvedValue({
      data: {
        id: 6,
        assignment_id: 19,
        owner_id: 7,
        owner_name: 'Synthetic assigned analyst',
        status: 'open',
        customer_confirmation: 'not_applicable',
        metadata: { routing_waiting_reason: 'no_authorized_available_analyst' },
      },
    });
    await wrapper.setProps({ actionId: 6 });
    await flushPromises();
    expect(wrapper.find('[data-testid="routing-waiting"]').exists()).toBe(
      false
    );
    expect(wrapper.text()).toContain('Synthetic assigned analyst');
    wrapper.unmount();
  });
  it('keeps exactly nine primary areas and preserves every legacy screen inside one area', () => {
    expect(AREAS).toHaveLength(9);
    SCREENS.forEach(screen =>
      expect(areaForScreen(screen), screen).toBeDefined()
    );
    expect(
      visibleAreas({ can_configure: false }).map(row => row.key)
    ).not.toContain('settings');
    expect(visibleAreas({ can_configure: true })).toHaveLength(9);
  });
  it('loads personal actions using the scoped native API and keeps URL pagination and filters', async () => {
    const wrapper = shallowMount(AnalystWorkspace, {
      props: { screen: 'actions' },
    });
    await flushPromises();
    expect(mocks.api.records).toHaveBeenCalledWith(
      '1',
      'actions',
      expect.objectContaining({
        mine: true,
        page: 2,
        q: 'Synthetic',
        per_page: 25,
      }),
      expect.anything()
    );
    const request = mocks.api.records.mock.calls[0][3];
    mocks.route.params.accountId = '2';
    await flushPromises();
    expect(request.signal.aborted).toBe(true);
    expect(mocks.api.records.mock.calls.at(-1)[0]).toBe('2');
    wrapper.unmount();
  });
  it('does not report success or close the result form when the server rejects the write', async () => {
    const wrapper = shallowMount(ActionCasePanel, {
      props: { actionId: 5, metadata },
    });
    await flushPromises();
    await wrapper.find('[data-testid="record-follow-up"]').trigger('click');
    mocks.api.saveRecord.mockRejectedValue({
      response: { data: { errors: ['Permission revoked'] } },
    });
    wrapper.findComponent({ name: 'ActionFollowUpDialog' }).vm.$emit('save', {
      next_step: 'Return',
      return_at: '2026-11-03T12:00:00Z',
    });
    await flushPromises();
    expect(wrapper.emitted('changed')).toBeUndefined();
    expect(
      wrapper.findComponent({ name: 'ActionFollowUpDialog' }).exists()
    ).toBe(true);
    expect(wrapper.text()).toContain('Permission revoked');
    expect(mocks.api.saveRecord).toHaveBeenCalledWith(
      '1',
      'actions',
      expect.objectContaining({ assignment_id: 19, lock_version: 2 }),
      5
    );
    wrapper.unmount();
  });
  it('clears an opened case when the identity changes and ignores the old response', async () => {
    let resolve;
    mocks.api.record.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const wrapper = shallowMount(ActionCasePanel, {
      props: { actionId: 5, metadata },
    });
    mocks.route.params.accountId = '2';
    await flushPromises();
    resolve({
      data: {
        id: 5,
        assignment_id: 999,
        customer_name: 'Old account confidential',
      },
    });
    await flushPromises();
    expect(wrapper.text()).not.toContain('Old account confidential');
    expect(mocks.api.channels).not.toHaveBeenCalledWith(
      '1',
      999,
      expect.anything()
    );
    wrapper.unmount();
  });

  it('clears private case details and invalidates the list when a write reveals revoked access', async () => {
    const wrapper = shallowMount(ActionCasePanel, {
      props: { actionId: 5, metadata },
    });
    await flushPromises();
    await wrapper.find('[data-testid="record-follow-up"]').trigger('click');
    mocks.api.saveRecord.mockRejectedValue({
      response: { status: 403, data: { errors: ['Denied after revocation'] } },
    });
    wrapper
      .findComponent({ name: 'ActionFollowUpDialog' })
      .vm.$emit('save', { result: 'Attempted update' });
    await flushPromises();
    expect(wrapper.emitted('changed')).toBeUndefined();
    expect(wrapper.emitted('invalidated')).toHaveLength(1);
    expect(wrapper.text()).not.toContain('Synthetic');
    expect(
      wrapper.findComponent({ name: 'ActionFollowUpDialog' }).exists()
    ).toBe(false);
    wrapper.unmount();
  });
});
