import { afterEach, describe, expect, it, vi } from 'vitest';
import { reactive } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import {
  createSnapshotSession,
  createSnapshotState,
  snapshotInput,
  decodeSnapshot,
  snapshotFields,
} from '../helpers/slaSnapshot';
import { createServiceDeskLifecycleClient } from 'dashboard/api/serviceDeskLifecycleClient';
import { ticket, deferred, httpError } from './fixtures';

const holder = vi.hoisted(() => ({
  session: null,
  recordSnapshot: vi.fn(),
  snapshot: vi.fn(),
}));
vi.mock('../composables/useServiceDesk', () => ({
  useServiceDesk: () => holder.session,
}));
vi.mock('dashboard/api/serviceDeskLifecycle', () => ({
  default: {
    recordSnapshot: (...args) => holder.recordSnapshot(...args),
    snapshot: (...args) => holder.snapshot(...args),
  },
}));
import SlaSnapshotEditor from '../components/SlaSnapshotEditor.vue';

const input = () => ({
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
const context = () => ({
  account_id: '1',
  user_id: '7',
  available: true,
  units: [{ id: '10' }],
  capabilities: {},
});
const nativeTicket = () =>
  ticket({
    permissions: { record_sla_snapshot: true, view_contract_conditions: true },
  });
const payload = (data = input(), options = {}) => ({
  contract_version: 1,
  account_id: '1',
  unit_id: '10',
  ticket_id: '20',
  snapshot: {
    id: '61',
    version: 2,
    permissions: { show: true },
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
  },
  ...options,
});
let wrapper;
afterEach(() => {
  wrapper?.unmount();
  wrapper = null;
  vi.clearAllMocks();
});

describe('native append-only SLA snapshot editor', () => {
  it('confirms the exact saved context, digest, version, provenance and JSON through a separate GET', async () => {
    const ctx = context();
    const current = nativeTicket();
    const state = createSnapshotState();
    const api = {
      recordSnapshot: vi
        .fn()
        .mockResolvedValue(payload(input(), { applied: true })),
      snapshot: vi.fn().mockResolvedValue(payload()),
    };
    const session = createSnapshotSession(
      api,
      () => ctx,
      () => current,
      state
    );
    const result = await session.apply(input());
    expect(state.status).toBe('confirmed');
    expect(result.id).toBe('61');
    expect(api.recordSnapshot).toHaveBeenCalledWith(
      '1',
      '20',
      input(),
      expect.any(AbortSignal)
    );
    expect(api.snapshot).toHaveBeenCalledWith(
      '1',
      '20',
      '61',
      expect.any(AbortSignal)
    );
    expect(result.input.calendar_conditions).toEqual(
      input().calendar_conditions
    );
  });
  it.each(['account_id', 'unit_id', 'ticket_id'])(
    'does not confirm a cross-context %s readback',
    async field => {
      const ctx = context();
      const current = nativeTicket();
      const state = createSnapshotState();
      const api = {
        recordSnapshot: vi
          .fn()
          .mockResolvedValue(payload(input(), { applied: true })),
        snapshot: vi
          .fn()
          .mockResolvedValue(payload(input(), { [field]: '999' })),
      };
      await createSnapshotSession(
        api,
        () => ctx,
        () => current,
        state
      ).apply(input());
      expect(state.status).toBe('readback_pending');
      expect(state.snapshot).toBeNull();
    }
  );
  it('does not convert a different native JSON/digest into a successful confirmation', async () => {
    const ctx = context();
    const current = nativeTicket();
    const state = createSnapshotState();
    const changed = input();
    changed.policy_conditions.clock_budgets_seconds.resolution = 999;
    const api = {
      recordSnapshot: vi
        .fn()
        .mockResolvedValue(payload(input(), { applied: true })),
      snapshot: vi.fn().mockResolvedValue(payload(changed)),
    };
    await createSnapshotSession(
      api,
      () => ctx,
      () => current,
      state
    ).apply(input());
    expect(state.status).toBe('readback_pending');
    expect(state.snapshot).toBeNull();
  });
  it('reconciles a lost GET with the exact receipt without repeating POST', async () => {
    const ctx = context();
    const current = nativeTicket();
    const state = createSnapshotState();
    const api = {
      recordSnapshot: vi
        .fn()
        .mockResolvedValue(payload(input(), { applied: true })),
      snapshot: vi
        .fn()
        .mockRejectedValueOnce(httpError(503))
        .mockResolvedValueOnce(payload()),
    };
    const session = createSnapshotSession(
      api,
      () => ctx,
      () => current,
      state
    );
    await session.apply(input());
    expect(state.status).toBe('readback_pending');
    await session.recover();
    expect(state.status).toBe('confirmed');
    expect(api.recordSnapshot).toHaveBeenCalledTimes(1);
    expect(api.snapshot).toHaveBeenCalledTimes(2);
  });
  it('keeps the same captured instant and input on an unknown POST retry, for native digest replay', async () => {
    const ctx = context();
    const current = nativeTicket();
    const state = createSnapshotState();
    const api = {
      recordSnapshot: vi
        .fn()
        .mockRejectedValueOnce(httpError(503))
        .mockResolvedValueOnce(payload(input(), { applied: true })),
      snapshot: vi.fn().mockResolvedValue(payload()),
    };
    const session = createSnapshotSession(
      api,
      () => ctx,
      () => current,
      state
    );
    await session.apply(input());
    await session.recover();
    expect(api.recordSnapshot.mock.calls.map(call => call[2])).toEqual([
      input(),
      input(),
    ]);
    expect(state.status).toBe('confirmed');
  });
  it('reports only a restricted receipt when the server withholds conditions and never GETs them', async () => {
    const ctx = context();
    const current = nativeTicket();
    const state = createSnapshotState();
    const api = {
      recordSnapshot: vi.fn().mockResolvedValue({
        ...payload(),
        applied: true,
        snapshot: { id: '61', version: 2, permissions: { show: false } },
      }),
      snapshot: vi.fn(),
    };
    await createSnapshotSession(
      api,
      () => ctx,
      () => current,
      state
    ).apply(input());
    expect(state.status).toBe('recorded_restricted');
    expect(state.snapshot).toEqual({
      id: '61',
      version: 2,
      permissions: { show: false },
    });
    expect(api.snapshot).not.toHaveBeenCalled();
  });
  it('stops reconciliation after native GET 404 revokes access without repeating POST', async () => {
    const ctx = context();
    const current = nativeTicket();
    const state = createSnapshotState();
    const api = {
      recordSnapshot: vi
        .fn()
        .mockResolvedValue(payload(input(), { applied: true })),
      snapshot: vi.fn().mockRejectedValue(httpError(404)),
    };
    const session = createSnapshotSession(
      api,
      () => ctx,
      () => current,
      state
    );
    await session.apply(input());
    expect(state.status).toBe('denied');
    expect(state.snapshot).toBeNull();
    await session.recover();
    expect(api.recordSnapshot).toHaveBeenCalledTimes(1);
    expect(api.snapshot).toHaveBeenCalledTimes(1);
  });
  it('clears and discards late receipts after account/operator context or ticket access is revoked', async () => {
    let ctx = context();
    const current = nativeTicket();
    const state = createSnapshotState();
    const response = deferred();
    const api = {
      recordSnapshot: vi.fn(() => response.promise),
      snapshot: vi.fn(),
    };
    const session = createSnapshotSession(
      api,
      () => ctx,
      () => current,
      state
    );
    const running = session.apply(input());
    ctx = { ...ctx, user_id: '9' };
    session.clear();
    response.resolve(payload(input(), { applied: true }));
    await running;
    expect(state.status).toBe('idle');
    expect(api.snapshot).not.toHaveBeenCalled();
    current.permissions.record_sla_snapshot = false;
    await session.apply(input());
    expect(api.recordSnapshot).toHaveBeenCalledTimes(1);
  });
  it('rejects server fields, credentials, missing provenance, invalid timezone and timestamps without an offset', () => {
    const invalid = [
      { ...input(), version: 2 },
      { ...input(), source_reference: '' },
      { ...input(), timezone: 'not/a-zone' },
      { ...input(), captured_at: '2026-10-08T10:00:00' },
      { ...input(), contract_conditions: { credentials: 'test-only' } },
    ];
    invalid.forEach(value => expect(() => snapshotInput(value)).toThrow());
    expect(() =>
      decodeSnapshot(
        payload(),
        { ...context(), available: false },
        nativeTicket()
      )
    ).toThrow();
  });
  it('uses only the native account/ticket snapshot endpoints and rejects a server digest in the input', async () => {
    const http = {
      post: vi
        .fn()
        .mockResolvedValue({ data: payload(input(), { applied: true }) }),
      get: vi.fn().mockResolvedValue({ data: payload() }),
    };
    const api = createServiceDeskLifecycleClient(http);
    const signal = new AbortController().signal;
    await api.recordSnapshot('1', '20', input(), signal);
    await api.snapshot('1', '20', '61', signal);
    expect(http.post).toHaveBeenCalledWith(
      '/api/v1/accounts/1/jrc_service_desk/tickets/20/sla_snapshots',
      { snapshot: input() },
      expect.objectContaining({ signal })
    );
    expect(http.get).toHaveBeenCalledWith(
      '/api/v1/accounts/1/jrc_service_desk/tickets/20/sla_snapshots/61',
      expect.objectContaining({ signal })
    );
    expect(() =>
      api.recordSnapshot('1', '20', {
        ...input(),
        payload_digest: 'a'.repeat(64),
      })
    ).toThrow();
  });
  it('requires every explicit field, performs no write until submit and clears fields after permission revocation', async () => {
    holder.session = {
      state: reactive({ status: 'ready', context: context() }),
      retry: vi.fn(),
      operations: { state: reactive({ revision: 0 }) },
    };
    holder.recordSnapshot.mockResolvedValue(
      payload(input(), { applied: true })
    );
    holder.snapshot.mockResolvedValue(payload());
    const Input = {
      props: ['modelValue', 'disabled', 'label'],
      emits: ['update:modelValue'],
      template:
        '<label>{{ label }}<input :value="modelValue" :disabled="disabled" @input="$emit(\'update:modelValue\', $event.target.value)" /></label>',
    };
    const Select = {
      props: ['modelValue', 'options', 'disabled'],
      emits: ['update:modelValue'],
      template:
        '<select :value="modelValue" :disabled="disabled" @change="$emit(\'update:modelValue\', $event.target.value)"><option value=""></option><option v-for="item in options" :key="item.value" :value="item.value">{{ item.label }}</option></select>',
    };
    const TextArea = {
      props: ['modelValue', 'disabled', 'label'],
      emits: ['update:modelValue'],
      template:
        '<label>{{ label }}<textarea :value="modelValue" :disabled="disabled" @input="$emit(\'update:modelValue\', $event.target.value)" /></label>',
    };
    wrapper = mount(SlaSnapshotEditor, {
      props: { ticket: nativeTicket() },
      global: {
        plugins: [
          createI18n({
            legacy: false,
            locale: 'en',
            missingWarn: false,
            fallbackWarn: false,
            messages: { en: {} },
          }),
        ],
        stubs: {
          Input,
          Select,
          TextArea,
          Button: {
            props: ['label', 'disabled'],
            template: '<button :disabled="disabled">{{ label }}</button>',
          },
        },
      },
    });
    await wrapper.find('button').trigger('click');
    expect(
      wrapper.find('[data-testid="snapshot-save"]').attributes('disabled')
    ).toBeDefined();
    await Promise.all(
      snapshotFields.map(async field => {
        const node = wrapper.find(`[data-testid="snapshot-${field}"]`);
        const control =
          node.element.tagName === 'SELECT'
            ? node
            : node.find(field.endsWith('_conditions') ? 'textarea' : 'input');
        await control.setValue(
          field.endsWith('_conditions')
            ? JSON.stringify(input()[field])
            : input()[field]
        );
      })
    );
    expect(holder.recordSnapshot).not.toHaveBeenCalled();
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    expect(holder.recordSnapshot).toHaveBeenCalledTimes(1);
    expect(wrapper.find('[data-testid="snapshot-confirmed"]').text()).toContain(
      'a'.repeat(64)
    );
    await wrapper.setProps({
      ticket: {
        ...nativeTicket(),
        permissions: { record_sla_snapshot: false },
      },
    });
    expect(wrapper.find('form').exists()).toBe(false);
    expect(wrapper.find('[data-testid="snapshot-confirmed"]').exists()).toBe(
      false
    );
  });
});
