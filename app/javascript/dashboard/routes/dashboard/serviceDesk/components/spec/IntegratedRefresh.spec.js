import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, reactive } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import messages from 'dashboard/i18n/locale/pt_BR/jrcServiceDesk.json';
import { contextPayload } from '../../__tests__/fixtures';
import { decodeClockProjection } from '../../helpers/clockProjection';

const mocks = vi.hoisted(() => ({ route: null, context: vi.fn() }));
vi.mock('vue-router', () => ({
  useRoute: () => mocks.route,
  useRouter: () => ({ replace: vi.fn() }),
}));
vi.mock('vuex', () => ({
  useStore: () => ({
    getters: {
      getCurrentUserID: '7',
      'accounts/isFeatureEnabledonAccount': () => true,
    },
  }),
}));
vi.mock('dashboard/api/serviceDesk', () => ({
  default: { context: (...args) => mocks.context(...args) },
}));
import { provideServiceDesk } from '../../composables/useServiceDesk';
import OverviewSignals from '../OverviewSignals.vue';

let wrapper;
let session;
const Root = defineComponent({
  setup() {
    session = provideServiceDesk();
    return {};
  },
  template: '<div />',
});
beforeEach(() => {
  mocks.route = reactive({
    name: 'jrc_service_desk_mine',
    params: { accountId: '1' },
  });
  mocks.context.mockResolvedValue(contextPayload());
});
afterEach(() => {
  wrapper?.unmount();
  vi.restoreAllMocks();
  vi.clearAllMocks();
});

describe('Integrated read refresh and server SLA presentation', () => {
  it('refreshes personal lists and indicators on focus even if authorization is unchanged', async () => {
    wrapper = mount(Root);
    await flushPromises();
    const before = session.operations.state.revision;
    window.dispatchEvent(new Event('focus'));
    await flushPromises();
    expect(mocks.context).toHaveBeenCalledTimes(2);
    expect(session.operations.state.revision).toBe(before + 1);
    expect(session.state.status).toBe('ready');
  });

  it.each(['new', 'edit', 'detail'])(
    'does not refresh a %s draft or pending close modal on background focus',
    async screen => {
      mocks.route.name = `jrc_service_desk_${screen}`;
      wrapper = mount(Root);
      await flushPromises();
      window.dispatchEvent(new Event('focus'));
      await flushPromises();
      expect(session.operations.state.revision).toBe(0);
      expect(session.state.status).toBe('ready');
    }
  );

  it('removes authorized content when access is revoked instead of reusing a successful cached result', async () => {
    wrapper = mount(Root);
    await flushPromises();
    mocks.context.mockRejectedValue({ response: { status: 403 } });
    window.dispatchEvent(new Event('focus'));
    await flushPromises();
    expect(session.state.status).toBe('denied');
    expect(session.state.context).toBeNull();
  });

  it('shows unavailable measurement without inventing zero breaches', () => {
    wrapper = mount(OverviewSignals, {
      props: { kind: 'risk', data: { sla: null } },
      global: {
        plugins: [
          createI18n({
            legacy: false,
            locale: 'pt_BR',
            messages: { pt_BR: messages },
          }),
        ],
        stubs: {
          Panel: { template: '<section><slot /></section>' },
          Button: true,
        },
      },
    });
    expect(wrapper.text()).toContain(
      messages.JRC_SERVICE_DESK.REFINEMENT.overview.unmeasured
    );
    expect(wrapper.find('.text-2xl').exists()).toBe(false);
  });

  it('uses the backend deadline classification rather than recalculating a business calendar in Vue', () => {
    const projection = decodeClockProjection({
      id: '1',
      kind: 'resolution',
      state: 'running',
      deadline_state: 'on_time',
      budget_seconds: 3600,
      elapsed_seconds: 3600,
      remaining_seconds: 0,
      consumed_percent: 100,
      breached: false,
      due_at: '2026-10-23T20:00:00Z',
      observed_at: '2026-10-27T12:00:00Z',
      timezone: 'America/Sao_Paulo',
    });
    expect(projection.deadline_state).toBe('on_time');
    expect(projection.breached).toBe(false);
  });
});
