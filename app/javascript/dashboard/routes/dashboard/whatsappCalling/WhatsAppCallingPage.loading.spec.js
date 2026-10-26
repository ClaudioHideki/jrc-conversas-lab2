import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { reactive, ref } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import WhatsAppCallingPage from './WhatsAppCallingPage.vue';

const mocks = vi.hoisted(() => ({
  inboxes: null,
  store: null,
  route: null,
  calls: null,
  session: null,
  actions: null,
  alert: vi.fn(),
  push: vi.fn(),
}));

vi.mock('vuex', () => ({ useStore: () => mocks.store }));
vi.mock('vue-router', () => ({
  useRoute: () => mocks.route,
  useRouter: () => ({ push: mocks.push }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: mocks.alert }));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => mocks.inboxes,
}));
vi.mock('dashboard/stores/calls', () => ({
  useCallsStore: () => mocks.calls,
}));
vi.mock('dashboard/composables/useWhatsappCallSession', () => ({
  useWhatsappCallSession: () => mocks.session,
}));
vi.mock('dashboard/composables/useCallSession', () => ({
  useCallActions: () => mocks.actions,
}));
vi.mock('dashboard/helper/inbox', () => ({
  VOICE_CALL_PROVIDERS: { WHATSAPP: 'whatsapp' },
  getVoiceCallProvider: inbox =>
    inbox.channel_type === 'Channel::Whatsapp' ? 'whatsapp' : null,
}));
vi.mock('dashboard/api/contacts', () => ({
  default: {
    get: vi.fn(),
    search: vi.fn(),
    getConversations: vi.fn(),
  },
}));
vi.mock('dashboard/api/channel/whatsapp/whatsappCallsAPI', () => ({
  default: { permission: vi.fn(), requestPermission: vi.fn() },
}));

enableAutoUnmount(afterEach);

const whatsappInboxes = () => [
  { id: 11, name: 'Synthetic WhatsApp A', channel_type: 'Channel::Whatsapp' },
  { id: 12, name: 'Synthetic WhatsApp B', medium: 'whatsapp' },
];
const emailInbox = () => ({
  id: 21,
  name: 'Synthetic email',
  channel_type: 'Channel::Email',
});

const deferred = () => {
  let resolve;
  const promise = new Promise(done => {
    resolve = done;
  });
  return { promise, resolve };
};

let http;
let configuration;
const listRequests = () =>
  http.get.mock.calls.filter(([url]) => url.endsWith('/conversations'));
const configurationRequests = () =>
  http.get.mock.calls.filter(([url]) =>
    url.endsWith('/whatsapp_calling_configuration')
  );

describe('WhatsApp Calling initial conversation loading', () => {
  beforeEach(() => {
    window.history.replaceState({}, '', '/app/accounts/1/whatsapp');
    mocks.inboxes = ref([...whatsappInboxes(), emailInbox()]);
    mocks.route = reactive({ params: { accountId: '1' } });
    mocks.store = { getters: {}, dispatch: vi.fn().mockResolvedValue(null) };
    mocks.calls = reactive({
      activeCall: null,
      incomingCalls: [],
      calls: [],
      hasActiveCall: false,
      hasIncomingCall: false,
      addCall: vi.fn(),
      dismissCall: vi.fn(),
    });
    mocks.session = {
      isInitiating: ref(false),
      initiateOutboundCall: vi.fn(),
      rejectIncomingCall: vi.fn(),
      endActiveCall: vi.fn(),
    };
    mocks.actions = {
      formattedCallDuration: ref('00:00'),
      isJoining: ref(false),
      joinCall: vi.fn(),
    };
    configuration = Promise.resolve({
      data: { enabled: false, status: 'not_configured', active: false },
    });
    http = {
      get: vi.fn((url, { params = {} } = {}) => {
        if (url.endsWith('/whatsapp_calling_configuration')) {
          return configuration;
        }
        if (url.endsWith('/conversations')) {
          return Promise.resolve({
            data: {
              data: {
                payload: [
                  {
                    id: params.inbox_id * 10,
                    inbox_id: params.inbox_id,
                    status: 'open',
                    meta: { sender: { name: `Contact ${params.inbox_id}` } },
                    last_activity_at: params.inbox_id,
                  },
                ],
              },
            },
          });
        }
        if (url.endsWith('/calls')) {
          return Promise.resolve({ data: { payload: [], meta: { count: 0 } } });
        }
        throw new Error(`Unexpected synthetic HTTP GET: ${url}`);
      }),
      post: vi.fn(() => {
        throw new Error('Unexpected HTTP mutation');
      }),
      patch: vi.fn(() => {
        throw new Error('Unexpected HTTP mutation');
      }),
      delete: vi.fn(() => {
        throw new Error('Unexpected HTTP mutation');
      }),
    };
    vi.stubGlobal('axios', http);
  });

  afterEach(() => {
    expect(http.post).not.toHaveBeenCalled();
    expect(http.patch).not.toHaveBeenCalled();
    expect(http.delete).not.toHaveBeenCalled();
    expect(mocks.session.initiateOutboundCall).not.toHaveBeenCalled();
    expect(mocks.session.rejectIncomingCall).not.toHaveBeenCalled();
    expect(mocks.session.endActiveCall).not.toHaveBeenCalled();
    expect(mocks.actions.joinCall).not.toHaveBeenCalled();
    expect(mocks.calls.addCall).not.toHaveBeenCalled();
    vi.unstubAllGlobals();
  });

  it('loads each preloaded WhatsApp inbox once with the existing request contract', async () => {
    const wrapper = mount(WhatsAppCallingPage);
    await flushPromises();

    expect(listRequests()).toHaveLength(2);
    expect(
      listRequests().map(([, options]) => options.params.inbox_id)
    ).toEqual([11, 12]);
    listRequests().forEach(([url, options]) => {
      expect(url).toBe('/api/v1/accounts/1/conversations');
      expect(options.params).toEqual(
        expect.objectContaining({ status: 'all', page: 1 })
      );
    });
    expect(configurationRequests()).toHaveLength(1);
    expect(
      http.get.mock.calls.filter(([url]) => url.endsWith('/calls'))
    ).toHaveLength(4);
    expect(wrapper.text()).toContain('Contact 11');
    expect(wrapper.text()).toContain('Contact 12');
  });

  it('loads inboxes that arrive after mounting an initially empty store', async () => {
    mocks.inboxes.value = [];
    const wrapper = mount(WhatsAppCallingPage);
    await flushPromises();
    expect(listRequests()).toHaveLength(0);

    mocks.inboxes.value = [...whatsappInboxes(), emailInbox()];
    await flushPromises();

    expect(listRequests()).toHaveLength(2);
    expect(wrapper.text()).toContain('Contact 11');
    expect(wrapper.text()).toContain('Contact 12');
  });

  it('does not reload conversations when pending configuration finishes', async () => {
    const pending = deferred();
    configuration = pending.promise;
    mount(WhatsAppCallingPage);
    await flushPromises();
    expect(listRequests()).toHaveLength(2);

    pending.resolve({ data: { enabled: false, active: false } });
    await flushPromises();

    expect(listRequests()).toHaveLength(2);
  });

  it('still refreshes the existing inbox lists when requested explicitly', async () => {
    const wrapper = mount(WhatsAppCallingPage);
    await flushPromises();
    expect(listRequests()).toHaveLength(2);

    await wrapper.get('button[title="Atualizar conversas"]').trigger('click');
    await flushPromises();

    expect(
      listRequests().map(([, options]) => options.params.inbox_id)
    ).toEqual([11, 12, 11, 12]);
    expect(configurationRequests()).toHaveLength(1);
    expect(wrapper.text()).toContain('Contact 11');
    expect(wrapper.text()).toContain('Contact 12');
  });

  it('reloads the authorized inbox projection after the store changes', async () => {
    const wrapper = mount(WhatsAppCallingPage);
    await flushPromises();

    mocks.inboxes.value = [whatsappInboxes()[1], emailInbox()];
    await flushPromises();

    expect(
      listRequests().map(([, options]) => options.params.inbox_id)
    ).toEqual([11, 12, 12]);
    expect(wrapper.text()).not.toContain('Contact 11');
    expect(wrapper.text()).toContain('Contact 12');

    mocks.inboxes.value = [emailInbox()];
    await flushPromises();
    expect(listRequests()).toHaveLength(3);
    expect(wrapper.text()).not.toContain('Contact 12');
    expect(wrapper.text()).toContain('Nenhuma conversa WhatsApp');
  });

  it('does not retry a denied conversation list because the component mounted', async () => {
    http.get.mockImplementationOnce(() =>
      Promise.reject(
        Object.assign(new Error('Synthetic access denied'), {
          response: { status: 403, data: { error: 'Access denied' } },
        })
      )
    );
    const wrapper = mount(WhatsAppCallingPage);
    await flushPromises();

    expect(listRequests()).toHaveLength(2);
    expect(mocks.alert).toHaveBeenCalledWith('Access denied');
    expect(wrapper.text()).not.toContain('Contact 11');
    expect(wrapper.text()).not.toContain('Contact 12');
    expect(wrapper.text()).toContain('Nenhuma conversa WhatsApp');
  });

  it('keeps conversation loading independent of unavailable calling configuration', async () => {
    configuration = Promise.reject(
      new Error('Synthetic configuration failure')
    );
    const wrapper = mount(WhatsAppCallingPage);
    await flushPromises();

    expect(listRequests()).toHaveLength(2);
    expect(configurationRequests()).toHaveLength(1);
    expect(wrapper.text()).toContain('Contact 11');
    expect(wrapper.text()).toContain('Contact 12');
  });
});
