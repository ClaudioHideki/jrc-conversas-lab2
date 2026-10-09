import { beforeEach, describe, expect, it, vi } from 'vitest';
import { reactive } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import TicketDetailView from '../TicketDetailView.vue';
import SlaSnapshotEditor from '../../components/SlaSnapshotEditor.vue';
import { snapshotFields } from '../../helpers/slaSnapshot';

const mocks = vi.hoisted(() => ({
  session: null,
  route: null,
  recordSnapshot: vi.fn(),
  snapshot: vi.fn(),
}));
vi.mock('vue-router', () => ({
  useRoute: () => mocks.route,
  useRouter: () => ({ push: vi.fn() }),
}));
vi.mock('../../composables/useServiceDesk', () => ({
  useServiceDesk: () => mocks.session,
}));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));
vi.mock('dashboard/api/serviceDeskLifecycle', () => ({
  default: {
    recordSnapshot: (...args) => mocks.recordSnapshot(...args),
    snapshot: (...args) => mocks.snapshot(...args),
  },
}));
const ticket = () => ({
  id: '3',
  account_id: '1',
  unit_id: '2',
  title: 'Verified ticket',
  description: 'Customer request',
  permissions: { view_notes: true, add_note: true },
});
const publication = (outcome = 'saved') => ({
  operation: 'add_interaction',
  account_id: '1',
  unit_id: '2',
  ticket_id: '3',
  result_id: '9',
  outcome,
});
const cockpit = {
  name: 'TicketCockpit',
  emits: ['updated'],
  template: '<div data-cockpit />',
};
const render = (stubs = {}) =>
  mount(TicketDetailView, {
    global: {
      stubs: {
        TicketCockpit: cockpit,
        Panel: { template: '<section><slot /></section>' },
        State: { props: ['status'], template: '<div>{{ status }}</div>' },
        TicketHeader: true,
        TicketSummary: true,
        TicketActivity: true,
        LifecyclePanel: true,
        SlaSnapshotEditor: true,
        TicketOperations: true,
        CustomerContextPanel: true,
        OperationsLinks: true,
        Button: true,
        TabBar: true,
        ...stubs,
      },
    },
  });

beforeEach(() => {
  vi.clearAllMocks();
  mocks.route = reactive({ params: { accountId: '1', ticketId: '3' } });
  mocks.session = {
    state: reactive({
      status: 'ready',
      context: {
        account_id: '1',
        user_id: '7',
        available: true,
        units: [{ id: '2' }],
      },
    }),
    accountId: reactive({ value: '1' }),
    userId: reactive({ value: '7' }),
    operations: { state: reactive({ revision: 0 }) },
    detail: reactive({ status: 'ready', record: ticket() }),
    resource() {
      return this.detail;
    },
    load: vi.fn(),
    resetResource: vi.fn(),
    retry: vi.fn(),
  };
});

describe('verified publication confirmation in the ticket detail', () => {
  it.each([true, false])(
    'shows the snapshot editor without requiring an unrelated lifecycle grant (%s)',
    async inspect => {
      mocks.session.detail.record.permissions = {
        view_sla: true,
        record_sla_snapshot: true,
        lifecycle_inspect: inspect,
      };
      const wrapper = render();
      await flushPromises();
      const nativeTabEvent = 'tab-changed';
      wrapper
        .findComponent({ name: 'TabBar' })
        .vm.$emit(nativeTabEvent, { value: 'sla' });
      await flushPromises();
      expect(
        wrapper.findAllComponents({ name: 'SlaSnapshotEditor' })
      ).toHaveLength(inspect ? 0 : 1);
      expect(
        wrapper.findAllComponents({ name: 'LifecyclePanel' })
      ).toHaveLength(inspect ? 1 : 0);
      mocks.session.detail.record.permissions = {
        view_sla: true,
        record_sla_snapshot: false,
        lifecycle_inspect: false,
      };
      await flushPromises();
      expect(
        wrapper.findComponent({ name: 'SlaSnapshotEditor' }).exists()
      ).toBe(false);
      wrapper.unmount();
    }
  );
  it.each(['saved', 'published_blocked'])(
    'keeps %s visible when the GET refresh unmounts the cockpit',
    async outcome => {
      const wrapper = render();
      await flushPromises();
      mocks.session.load.mockImplementationOnce(() => {
        mocks.session.detail.status = 'loading';
        mocks.session.detail.record = null;
      });
      wrapper.findComponent(cockpit).vm.$emit('updated', publication(outcome));
      await flushPromises();
      expect(wrapper.find('[data-cockpit]').exists()).toBe(false);
      expect(wrapper.get('[role="status"]').text()).toBe(
        `JRC_SERVICE_DESK.R2.${outcome}`
      );
      mocks.session.detail.record = ticket();
      mocks.session.detail.status = 'ready';
      await flushPromises();
      expect(wrapper.find('[data-cockpit]').exists()).toBe(true);
      expect(wrapper.get('[role="status"]').text()).toBe(
        `JRC_SERVICE_DESK.R2.${outcome}`
      );
      wrapper.unmount();
    }
  );
  it.each(['account', 'ticket', 'authorization'])(
    'clears the verified confirmation on %s change',
    async change => {
      const wrapper = render();
      await flushPromises();
      wrapper.findComponent(cockpit).vm.$emit('updated', publication());
      await flushPromises();
      expect(wrapper.find('[role="status"]').exists()).toBe(true);
      if (change === 'account') mocks.route.params.accountId = '8';
      if (change === 'ticket') mocks.route.params.ticketId = '4';
      if (change === 'authorization') mocks.session.state.status = 'denied';
      await flushPromises();
      expect(wrapper.find('[role="status"]').exists()).toBe(false);
      wrapper.unmount();
    }
  );
  it('clears confirmation when the refreshed ticket no longer allows notes', async () => {
    const wrapper = render();
    await flushPromises();
    wrapper.findComponent(cockpit).vm.$emit('updated', publication());
    await flushPromises();
    mocks.session.detail.record = {
      ...ticket(),
      permissions: { view_notes: false, add_note: false },
    };
    await flushPromises();
    expect(wrapper.find('[role="status"]').exists()).toBe(false);
    wrapper.unmount();
  });
  it('does not turn unrelated writes or an acknowledgement for another scope into confirmation', async () => {
    const wrapper = render();
    await flushPromises();
    wrapper.findComponent(cockpit).vm.$emit('updated');
    await flushPromises();
    expect(wrapper.find('[role="status"]').exists()).toBe(false);
    wrapper
      .findComponent(cockpit)
      .vm.$emit('updated', { ...publication(), account_id: '8' });
    await flushPromises();
    expect(wrapper.find('[role="status"]').exists()).toBe(false);
    wrapper.unmount();
  });
});

const snapshotInput = () => ({
  source_system: 'Native commercial',
  source_reference: 'contract:42',
  source_version: '2',
  policy_key: 'service-policy',
  policy_version: '1',
  calendar_key: 'unit-calendar',
  calendar_version: '3',
  calendar_scope: 'unit',
  timezone: 'America/Sao_Paulo',
  captured_at: '2026-10-08T10:00:00-03:00',
  contract_conditions: { contract_id: 42 },
  policy_conditions: { clock_budgets_seconds: { resolution: 3600 } },
  calendar_conditions: {
    format: 'jrc-sd-snapshot-calendar-v1',
    weekly: { 1: [['09:00', '17:00']] },
  },
});
const snapshotTicket = (show = true) => ({
  ...ticket(),
  permissions: {
    view_sla: true,
    record_sla_snapshot: true,
    view_contract_conditions: show,
    lifecycle_inspect: false,
  },
});
const snapshotPayload = (show = true) => {
  const data = snapshotInput();
  return {
    contract_version: 1,
    account_id: '1',
    unit_id: '2',
    ticket_id: '3',
    snapshot: {
      id: '61',
      version: 2,
      permissions: { show },
      ...(show
        ? {
            payload_digest: 'a'.repeat(64),
            source: {
              system: data.source_system,
              reference: data.source_reference,
              version: data.source_version,
            },
            policy: { key: data.policy_key, version: data.policy_version },
            calendar: {
              key: data.calendar_key,
              version: data.calendar_version,
              scope: data.calendar_scope,
            },
            timezone: data.timezone,
            captured_at: '2026-10-08T13:00:00.000000Z',
            applied_at: '2026-10-08T13:01:00.000000Z',
            conditions: {
              contract: data.contract_conditions,
              policy: data.policy_conditions,
              calendar: data.calendar_conditions,
            },
          }
        : {}),
    },
  };
};
const snapshotStubs = {
  SlaSnapshotEditor: false,
  Input: {
    props: ['modelValue', 'disabled', 'label'],
    emits: ['update:modelValue'],
    template:
      '<label>{{ label }}<input :value="modelValue" :disabled="disabled" @input="$emit(\'update:modelValue\', $event.target.value)" /></label>',
  },
  Select: {
    props: ['modelValue', 'options', 'disabled'],
    emits: ['update:modelValue'],
    template:
      '<select :value="modelValue" :disabled="disabled" @change="$emit(\'update:modelValue\', $event.target.value)"><option value=""></option><option v-for="item in options" :key="item.value" :value="item.value">{{ item.label }}</option></select>',
  },
  TextArea: {
    props: ['modelValue', 'disabled', 'label'],
    emits: ['update:modelValue'],
    template:
      '<label>{{ label }}<textarea :value="modelValue" :disabled="disabled" @input="$emit(\'update:modelValue\', $event.target.value)" /></label>',
  },
  Button: {
    props: ['label', 'disabled'],
    template: '<button :disabled="disabled">{{ label }}</button>',
  },
};
// Exercise the actual editor, native ACK/GET reconciliation and parent refresh.
const submitSnapshot = async (show = true) => {
  mocks.session.detail.record = snapshotTicket(show);
  mocks.recordSnapshot.mockResolvedValue({
    ...snapshotPayload(show),
    applied: true,
  });
  mocks.snapshot.mockResolvedValue(snapshotPayload());
  const wrapper = render(snapshotStubs);
  await flushPromises();
  const nativeTabEvent = 'tab-changed';
  wrapper
    .findComponent({ name: 'TabBar' })
    .vm.$emit(nativeTabEvent, { value: 'sla' });
  await flushPromises();
  await wrapper
    .findComponent(SlaSnapshotEditor)
    .find('button')
    .trigger('click');
  await Promise.all(
    snapshotFields.map(async field => {
      const node = wrapper.get(`[data-testid="snapshot-${field}"]`);
      const control =
        node.element.tagName === 'SELECT'
          ? node
          : node.get(field.endsWith('_conditions') ? 'textarea' : 'input');
      await control.setValue(
        field.endsWith('_conditions')
          ? JSON.stringify(snapshotInput()[field])
          : snapshotInput()[field]
      );
    })
  );
  mocks.session.load.mockClear();
  mocks.session.load.mockImplementationOnce(() => {
    mocks.session.detail.status = 'loading';
    mocks.session.detail.record = null;
  });
  await wrapper.get('[data-testid="sla-snapshot-form"]').trigger('submit');
  await flushPromises();
  return wrapper;
};
const completeSnapshotRefresh = async (show = true) => {
  mocks.session.detail.record = snapshotTicket(show);
  mocks.session.detail.status = 'ready';
  await flushPromises();
};

describe('snapshot confirmation through the integrated ticket refresh', () => {
  it('retains only the verified receipt after one current-ticket GET and preserves the SLA tab', async () => {
    const wrapper = await submitSnapshot();
    expect(mocks.recordSnapshot).toHaveBeenCalledWith(
      '1',
      '3',
      snapshotInput(),
      expect.any(AbortSignal)
    );
    expect(mocks.snapshot).toHaveBeenCalledWith(
      '1',
      '3',
      '61',
      expect.any(AbortSignal)
    );
    expect(mocks.recordSnapshot).toHaveBeenCalledTimes(1);
    expect(mocks.snapshot).toHaveBeenCalledTimes(1);
    expect(mocks.session.load).toHaveBeenCalledExactlyOnceWith(
      'ticket:detail',
      'tickets',
      {},
      '3'
    );
    expect(mocks.session.operations.state.revision).toBe(0);
    expect(wrapper.find('[data-testid="snapshot-confirmed"]').exists()).toBe(
      false
    );
    expect(wrapper.findComponent(SlaSnapshotEditor).exists()).toBe(false);
    await completeSnapshotRefresh();
    const receipt = wrapper.get('[data-testid="snapshot-confirmed"]');
    expect(receipt.text()).toContain(
      'JRC_SERVICE_DESK.SNAPSHOT.feedback.confirmed'
    );
    expect(receipt.text()).toContain('a'.repeat(64));
    expect(wrapper.findComponent(SlaSnapshotEditor).exists()).toBe(true);
    expect(wrapper.find('[data-testid="sla-snapshot-form"]').exists()).toBe(
      false
    );
    expect(mocks.session.load).toHaveBeenCalledTimes(1);
    wrapper.unmount();
  });
  it.each([
    'route_account',
    'route_ticket',
    'ticket_account',
    'ticket_unit',
    'context_user',
    'session_user',
    'module_access',
    'unit_access',
    'record_grant',
    'conditions_grant',
    'authorization',
    'not_found',
  ])(
    'clears the verified receipt on current %s changes and never revives it',
    async change => {
      const wrapper = await submitSnapshot();
      await completeSnapshotRefresh();
      expect(
        wrapper.get('[data-testid="snapshot-confirmed"]').text()
      ).toContain('a'.repeat(64));
      if (change === 'route_account') mocks.route.params.accountId = '8';
      if (change === 'route_ticket') mocks.route.params.ticketId = '4';
      if (change === 'ticket_account')
        mocks.session.detail.record.account_id = '8';
      if (change === 'ticket_unit') mocks.session.detail.record.unit_id = '4';
      if (change === 'context_user') mocks.session.state.context.user_id = '9';
      if (change === 'session_user') mocks.session.userId.value = '9';
      if (change === 'module_access')
        mocks.session.state.context.available = false;
      if (change === 'unit_access') mocks.session.state.context.units = [];
      if (change === 'record_grant')
        mocks.session.detail.record.permissions.record_sla_snapshot = false;
      if (change === 'conditions_grant')
        mocks.session.detail.record.permissions.view_contract_conditions = false;
      if (change === 'authorization') mocks.session.state.status = 'denied';
      if (change === 'not_found') mocks.session.detail.status = 'not_found';
      await flushPromises();
      expect(wrapper.find('[data-testid="snapshot-confirmed"]').exists()).toBe(
        false
      );
      mocks.route.params = { accountId: '1', ticketId: '3' };
      mocks.session.state.status = 'ready';
      mocks.session.state.context = {
        account_id: '1',
        user_id: '7',
        available: true,
        units: [{ id: '2' }],
      };
      mocks.session.userId.value = '7';
      await completeSnapshotRefresh();
      expect(wrapper.find('[data-testid="snapshot-confirmed"]').exists()).toBe(
        false
      );
      expect(mocks.recordSnapshot).toHaveBeenCalledTimes(1);
      expect(mocks.snapshot).toHaveBeenCalledTimes(1);
      wrapper.unmount();
    }
  );
  it('retains a restricted native receipt without reading or promoting it to conditions access', async () => {
    const wrapper = await submitSnapshot(false);
    expect(mocks.recordSnapshot).toHaveBeenCalledTimes(1);
    expect(mocks.snapshot).not.toHaveBeenCalled();
    expect(wrapper.find('[data-testid="snapshot-confirmed"]').exists()).toBe(
      false
    );
    await completeSnapshotRefresh(false);
    expect(wrapper.get('[data-testid="snapshot-confirmed"]').text()).toContain(
      'JRC_SERVICE_DESK.SNAPSHOT.feedback.recorded_restricted'
    );
    expect(
      wrapper.get('[data-testid="snapshot-confirmed"]').text()
    ).not.toContain('a'.repeat(64));
    mocks.session.detail.record.permissions.view_contract_conditions = true;
    await flushPromises();
    expect(wrapper.get('[data-testid="snapshot-confirmed"]').text()).toContain(
      'JRC_SERVICE_DESK.SNAPSHOT.feedback.recorded_restricted'
    );
    expect(mocks.snapshot).not.toHaveBeenCalled();
    expect(mocks.session.operations.state.revision).toBe(0);
    wrapper.unmount();
  });
});
