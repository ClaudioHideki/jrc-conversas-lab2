import { config, mount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import { useEventBus } from '@vueuse/core';
import { quickActionTarget } from '../useQuickActionTarget';
import { createI18n } from 'vue-i18n';
import ptBR from 'dashboard/i18n/locale/pt_BR';
import en from 'dashboard/i18n/locale/en';
import GlobalQuickActions from '../GlobalQuickActions.vue';
import ConversationQuickActions from '../../Conversation/ConversationHome/ConversationQuickActions.vue';

const mocks = vi.hoisted(() => ({
  home: null,
  route: null,
  push: vi.fn(),
  dispatch: vi.fn(),
  open: vi.fn(),
  success: vi.fn(),
  nico: vi.fn(),
  ask: vi.fn(),
  alert: vi.fn(),
}));
vi.mock('../useQuickActionAccess', () => ({
  useQuickActionAccess: () => mocks.home,
}));
vi.mock('dashboard/components-next/jrcCopilot/JrcCopilotLauncher.vue', () => ({
  default: { props: ['docked'], template: '<div data-nico-launcher />' },
}));
vi.mock('vue-router', async importOriginal => ({
  ...(await importOriginal()),
  useRouter: () => ({ push: mocks.push }),
  useRoute: () => mocks.route,
}));
vi.mock('vuex', () => ({ useStore: () => ({ dispatch: mocks.dispatch }) }));
vi.mock('dashboard/composables', () => ({ useAlert: mocks.alert }));
vi.mock('dashboard/components-next/jrcCopilot/useJrcCopilot', () => ({
  useJrcCopilot: () => ({ openQuick: mocks.nico, openWithPrompt: mocks.ask }),
}));
vi.mock(
  'dashboard/components-next/Contacts/ContactsForm/CreateNewContactDialog.vue',
  () => ({
    default: {
      name: 'CreateNewContactDialog',
      emits: ['create'],
      setup(_, { expose }) {
        expose({
          open: mocks.open,
          dialogRef: { open: mocks.open },
          onSuccess: mocks.success,
        });
      },
      template: '<div data-contact-dialog />',
    },
  })
);

describe('Global quick actions preserve existing handlers', () => {
  const plugins = config.global.plugins;
  let wrapper;
  beforeEach(() => {
    config.global.plugins = [
      createI18n({
        legacy: false,
        locale: 'pt_BR',
        fallbackLocale: 'en',
        messages: { pt_BR: ptBR, en },
      }),
    ];
    mocks.route = {
      name: 'jrc_cockpit',
      params: { accountId: '1' },
      fullPath: '/app/accounts/1/cockpit',
    };
    mocks.home = {
      accountId: ref(1),
      userId: ref(7),
      user: ref({ name: 'Usuário Teste' }),
      crmAllowed: ref(true),
      summary: ref({
        conversations_waiting: 3,
        missed_calls: null,
        sla_risk_count: 2,
        pending_tasks: 5,
      }),
      generatedAt: ref('2026-09-30T12:00:00Z'),
      failed: ref(false),
      loading: ref(false),
      refresh: vi.fn(),
      actions: ref([
        {
          key: 'CONTACT',
          command: 'contact',
          icon: 'i-lucide-user-round-plus',
          tone: 'blue',
        },
        {
          key: 'CALL',
          to: { name: 'ramal_index', params: { accountId: 1 } },
          icon: 'i-lucide-phone-call',
          tone: 'teal',
        },
        {
          key: 'LEAD',
          to: {
            name: 'crm_leads',
            params: { accountId: 1 },
            query: { new: '1' },
          },
          icon: 'i-lucide-target',
          tone: 'violet',
        },
        {
          key: 'NICO',
          command: 'nico',
          icon: 'i-lucide-sparkles',
          tone: 'violet',
        },
      ]),
    };
    mocks.dispatch.mockResolvedValue({});
  });
  afterEach(() => {
    wrapper?.unmount();
    config.global.plugins = plugins;
    document.documentElement.classList.remove('dark');
  });

  it('opens the original modal and routes without performing writes on shortcut clicks', async () => {
    wrapper = mount(GlobalQuickActions);
    await wrapper.get('button[aria-label="Novo contato"]').trigger('click');
    expect(mocks.open).toHaveBeenCalledOnce();
    await wrapper.get('button[aria-label="Nova ligação"]').trigger('click');
    expect(mocks.push).toHaveBeenCalledWith({
      name: 'ramal_index',
      params: { accountId: 1 },
    });
    await wrapper.get('button[aria-label="Novo lead"]').trigger('click');
    expect(mocks.push).toHaveBeenLastCalledWith({
      name: 'crm_leads',
      params: { accountId: 1 },
      query: { new: '1' },
    });
    expect(mocks.dispatch).not.toHaveBeenCalled();
  });

  it('rejects a stale action after permissions are removed', () => {
    wrapper = mount(GlobalQuickActions);
    mocks.home.actions.value = [];
    wrapper.findComponent(ConversationQuickActions).vm.$emit('select', 'LEAD');
    expect(mocks.push).not.toHaveBeenCalled();
  });

  it('reopens the existing CRM form on repeated shortcut clicks without changing its destination', async () => {
    mocks.route.name = 'crm_leads';
    mocks.push.mockResolvedValue(undefined);
    const listener = vi.fn();
    const stop = useEventBus(quickActionTarget).on(listener);
    wrapper = mount(GlobalQuickActions);
    await wrapper.get('button[aria-label="Novo lead"]').trigger('click');
    await flushPromises();
    await wrapper.get('button[aria-label="Novo lead"]').trigger('click');
    await flushPromises();
    expect(mocks.push).toHaveBeenLastCalledWith({
      name: 'crm_leads',
      params: { accountId: 1 },
      query: { new: '1' },
    });
    expect(listener).toHaveBeenCalledTimes(2);
    expect(listener).toHaveBeenLastCalledWith(
      { name: 'crm_leads', accountId: 1 },
      undefined
    );
    stop();
  });

  it('uses the existing NICO and shows only one docked avatar', async () => {
    wrapper = mount(GlobalQuickActions);
    await wrapper
      .get('button[aria-label="Conversar com o NICO"]')
      .trigger('click');
    expect(mocks.nico).toHaveBeenCalledOnce();
    expect(wrapper.findAll('[data-nico-launcher]')).toHaveLength(1);
  });

  it('opens the compact menu and closes it with Escape and after selecting an action', async () => {
    wrapper = mount(GlobalQuickActions);
    const toggle = wrapper.get(
      'button[aria-controls="global-quick-actions-list"]'
    );
    expect(toggle.attributes('aria-expanded')).toBe('false');
    await toggle.trigger('click');
    expect(toggle.attributes('aria-expanded')).toBe('true');
    await wrapper.trigger('keydown', { key: 'Escape' });
    expect(toggle.attributes('aria-expanded')).toBe('false');
    await toggle.trigger('click');
    await wrapper.get('button[aria-label="Nova ligação"]').trigger('click');
    expect(toggle.attributes('aria-expanded')).toBe('false');
  });

  it('saves contacts through the existing store and only confirms actual success', async () => {
    wrapper = mount(GlobalQuickActions);
    const payload = { name: 'Contato de teste' };
    const dialog = wrapper.findComponent({ name: 'CreateNewContactDialog' });
    mocks.dispatch.mockRejectedValueOnce(new Error('denied'));
    dialog.vm.$emit('create', payload);
    await flushPromises();
    expect(mocks.success).not.toHaveBeenCalled();
    expect(mocks.alert).toHaveBeenCalledWith(
      expect.stringContaining('Não foi possível')
    );
    dialog.vm.$emit('create', payload);
    await flushPromises();
    expect(mocks.dispatch).toHaveBeenCalledWith('contacts/create', payload);
    expect(mocks.success).toHaveBeenCalledOnce();
  });

  it('remounts the dialog on account/user change and ignores a late contact save response', async () => {
    let finish;
    mocks.dispatch.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    wrapper = mount(GlobalQuickActions);
    const original = wrapper.findComponent({
      name: 'CreateNewContactDialog',
    }).vm;
    original.$emit('create', { name: 'Teste' });
    mocks.home.accountId.value = 2;
    await flushPromises();
    expect(
      wrapper.findComponent({ name: 'CreateNewContactDialog' }).vm === original
    ).toBe(false);
    finish({});
    await flushPromises();
    expect(mocks.success).not.toHaveBeenCalled();
    expect(mocks.alert).not.toHaveBeenCalled();
    mocks.home.actions.value = [];
    wrapper
      .findComponent({ name: 'CreateNewContactDialog' })
      .vm.$emit('create', {});
    expect(mocks.dispatch).toHaveBeenCalledTimes(1);
  });
});
