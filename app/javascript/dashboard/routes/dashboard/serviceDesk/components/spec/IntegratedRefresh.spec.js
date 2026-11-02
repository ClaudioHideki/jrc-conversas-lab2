import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, reactive } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import messages from 'dashboard/i18n/locale/pt_BR/jrcServiceDesk.json';
import { contextPayload, deferred } from '../../__tests__/fixtures';
import { decodeClockProjection } from '../../helpers/clockProjection';

const mocks = vi.hoisted(() => ({ route: null, user: null, context: vi.fn() }));
vi.mock('vue-router', () => ({
  useRoute: () => mocks.route,
  useRouter: () => ({ replace: vi.fn() }),
}));
vi.mock('vuex', () => ({
  useStore: () => ({
    getters: {
      get getCurrentUserID() {
        return mocks.user.id;
      },
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
  mocks.user = reactive({ id: '7' });
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

  it.each([
    ['focus', 'visibilitychange'],
    ['visibilitychange', 'focus'],
  ])(
    'shares a single revalidation for concurrent %s and %s events',
    async (first, second) => {
      vi.spyOn(document, 'visibilityState', 'get').mockReturnValue('visible');
      wrapper = mount(Root);
      await flushPromises();
      const response = deferred();
      mocks.context.mockReturnValueOnce(response.promise);
      const before = session.operations.state.revision;

      (first === 'focus' ? window : document).dispatchEvent(new Event(first));
      (second === 'focus' ? window : document).dispatchEvent(new Event(second));
      expect(mocks.context).toHaveBeenCalledTimes(2);
      expect(session.operations.state.revision).toBe(before);

      response.resolve(contextPayload());
      await flushPromises();
      expect(session.operations.state.revision).toBe(before + 1);
      expect(session.state.status).toBe('ready');

      window.dispatchEvent(new Event('focus'));
      await flushPromises();
      expect(mocks.context).toHaveBeenCalledTimes(3);
      expect(session.operations.state.revision).toBe(before + 2);
    }
  );

  it('does not revalidate or reload reads while the document is hidden', async () => {
    wrapper = mount(Root);
    await flushPromises();
    vi.spyOn(document, 'visibilityState', 'get').mockReturnValue('hidden');
    window.dispatchEvent(new Event('focus'));
    document.dispatchEvent(new Event('visibilitychange'));
    await flushPromises();
    expect(mocks.context).toHaveBeenCalledTimes(1);
    expect(session.operations.state.revision).toBe(0);
  });

  it.each(['account', 'user'])(
    'does not let a delayed refresh reload or release the new %s refresh',
    async identity => {
      vi.spyOn(document, 'visibilityState', 'get').mockReturnValue('visible');
      wrapper = mount(Root);
      await flushPromises();
      const oldResponse = deferred();
      mocks.context.mockReturnValueOnce(oldResponse.promise);
      window.dispatchEvent(new Event('focus'));
      const nextContext = contextPayload();
      if (identity === 'account') {
        nextContext.account_id = '2';
        nextContext.units.forEach(unit => {
          unit.account_id = '2';
          unit.operator_company.account_id = '2';
        });
      } else {
        nextContext.user_id = '8';
      }
      mocks.context.mockResolvedValue(nextContext);
      if (identity === 'account') mocks.route.params.accountId = '2';
      else mocks.user.id = '8';
      await flushPromises();
      expect(session.state.status).toBe('ready');
      expect(session.state.context.account_id).toBe(nextContext.account_id);
      expect(session.state.context.user_id).toBe(nextContext.user_id);
      const before = session.operations.state.revision;

      const newResponse = deferred();
      mocks.context.mockReturnValueOnce(newResponse.promise);
      window.dispatchEvent(new Event('focus'));
      oldResponse.resolve(contextPayload());
      await flushPromises();
      expect(session.operations.state.revision).toBe(before);
      document.dispatchEvent(new Event('visibilitychange'));
      expect(mocks.context).toHaveBeenCalledTimes(4);

      newResponse.resolve(nextContext);
      await flushPromises();
      expect(session.operations.state.revision).toBe(before + 1);
      expect(session.state.context.account_id).toBe(nextContext.account_id);
      expect(session.state.context.user_id).toBe(nextContext.user_id);
    }
  );

  it('does not reload a newly selected screen when the previous screen refresh finishes', async () => {
    wrapper = mount(Root);
    await flushPromises();
    const response = deferred();
    mocks.context.mockReturnValueOnce(response.promise);
    window.dispatchEvent(new Event('focus'));
    mocks.route.name = 'jrc_service_desk_overview';
    response.resolve(contextPayload());
    await flushPromises();
    expect(session.operations.state.revision).toBe(0);
    window.dispatchEvent(new Event('focus'));
    await flushPromises();
    expect(session.operations.state.revision).toBe(1);
  });

  it('does not reuse a refresh after leaving and returning to the same screen', async () => {
    wrapper = mount(Root);
    await flushPromises();
    const response = deferred();
    mocks.context.mockReturnValueOnce(response.promise);
    window.dispatchEvent(new Event('focus'));
    mocks.route.name = 'jrc_service_desk_overview';
    mocks.route.name = 'jrc_service_desk_mine';
    response.resolve(contextPayload());
    await flushPromises();
    expect(session.operations.state.revision).toBe(0);
    window.dispatchEvent(new Event('focus'));
    await flushPromises();
    expect(session.operations.state.revision).toBe(1);
  });

  it('does not duplicate read reloads when a changed authorization projection already restarts the session', async () => {
    wrapper = mount(Root);
    await flushPromises();
    const context = session.state.context;
    mocks.context.mockResolvedValue(
      contextPayload({
        effective_permissions: ['jrc_service_desk_module_view'],
      })
    );
    window.dispatchEvent(new Event('focus'));
    await flushPromises();
    expect(mocks.context).toHaveBeenCalledTimes(3);
    expect(session.state.status).toBe('ready');
    expect(session.state.context).not.toBe(context);
    expect(session.state.context.effective_permissions).toEqual([
      'jrc_service_desk_module_view',
    ]);
    expect(session.operations.state.revision).toBe(0);
  });

  it('ignores a refresh that finishes after the provider unmounts', async () => {
    wrapper = mount(Root);
    await flushPromises();
    const response = deferred();
    mocks.context.mockReturnValueOnce(response.promise);
    window.dispatchEvent(new Event('focus'));
    wrapper.unmount();
    wrapper = null;
    response.resolve(contextPayload());
    await flushPromises();
    expect(session.state.status).toBe('idle');
    expect(session.state.context).toBeNull();
    expect(session.operations.state.revision).toBe(0);
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
    vi.spyOn(document, 'visibilityState', 'get').mockReturnValue('visible');
    wrapper = mount(Root);
    await flushPromises();
    mocks.context.mockRejectedValue({ response: { status: 403 } });
    window.dispatchEvent(new Event('focus'));
    document.dispatchEvent(new Event('visibilitychange'));
    await flushPromises();
    expect(mocks.context).toHaveBeenCalledTimes(2);
    expect(session.state.status).toBe('denied');
    expect(session.state.context).toBeNull();
    expect(session.operations.state.revision).toBe(0);
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
