import { afterEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, reactive, ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { decodeContext } from '../../helpers/contracts';
import {
  collection,
  contextPayload,
  deferred,
  httpError,
  identity,
} from '../../__tests__/fixtures';

const client = vi.hoisted(() => ({ report: vi.fn() }));
vi.mock('dashboard/api/serviceDeskOperationsV2', () => ({ default: client }));
import { useSupervisionReport } from '../useSupervisionReport';

const payload = (query = {}) => ({
  ...collection(),
  projection: 'authorized_service_desk_report_v2',
  dashboard: {
    total: 1,
    active: 1,
    phases: { open: 1, waiting: 0, resolved: 0, closed: 0, cancelled: 0 },
    by_status: [{ id: '1', name: 'Open', phase: 'open', count: 1 }],
    filters: query,
    generated_at: '2026-10-26T12:00:00Z',
    supervision: {
      timezone: 'UTC',
      sla: null,
      by_agent: [],
      capacity: [],
      evolution: [],
      top_categories: [],
      tasks: null,
      approvals: null,
    },
  },
});
let wrapper;
afterEach(() => {
  wrapper?.unmount();
  vi.clearAllMocks();
});
const render = () => {
  const context = contextPayload({
    effective_permissions: ['jrc_service_desk_tickets_view_all'],
  });
  context.capabilities.reports = { index: true };
  const session = {
    state: reactive({
      status: 'ready',
      context: decodeContext(context, identity),
    }),
    operations: { state: reactive({ revision: 0 }) },
  };
  const query = ref({});
  let report;
  client.report.mockResolvedValue(payload());
  wrapper = mount(
    defineComponent({
      setup() {
        report = useSupervisionReport(session, () => query.value);
        return {};
      },
      template: '<div />',
    })
  );
  return {
    session,
    query,
    get report() {
      return report;
    },
  };
};

describe('supervision background updates', () => {
  it('retains the confirmed report while a periodic same-scope read is pending', async () => {
    const state = render();
    await flushPromises();
    expect(state.report.status.value).toBe('ready');
    const previous = state.report.result.value;
    const response = deferred();
    client.report.mockReturnValueOnce(response.promise);
    state.session.operations.state.revision += 1;
    await flushPromises();
    expect(state.report.status.value).toBe('ready');
    expect(state.report.result.value).toBe(previous);
    response.resolve(payload());
    await flushPromises();
    expect(state.report.result.value).not.toBe(previous);
  });

  it('clears the report immediately on filter change', async () => {
    const state = render();
    await flushPromises();
    const response = deferred();
    client.report.mockReturnValueOnce(response.promise);
    state.query.value = { unit_id: '10' };
    await flushPromises();
    expect(state.report.result.value).toBeNull();
    expect(state.report.status.value).toBe('loading');
    response.resolve(payload({ unit_id: '10' }));
    await flushPromises();
    expect(state.report.status.value).toBe('ready');
  });

  it('clears confirmed report after a denied background response', async () => {
    const state = render();
    await flushPromises();
    const response = deferred();
    client.report.mockReturnValueOnce(response.promise);
    state.session.operations.state.revision += 1;
    await flushPromises();
    response.reject(httpError(403));
    await flushPromises();
    expect(state.report.status.value).toBe('denied');
    expect(state.report.result.value).toBeNull();
  });
});
