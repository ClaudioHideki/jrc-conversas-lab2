import { config, mount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import { createI18n } from 'vue-i18n';
import ptBR from 'dashboard/i18n/locale/pt_BR';
import en from 'dashboard/i18n/locale/en';
import ConversationHome from '../ConversationHome.vue';
import ConversationQuickActions from '../ConversationQuickActions.vue';

const mocks = vi.hoisted(() => ({
  home: null,
  push: vi.fn(),
  dispatch: vi.fn(),
  open: vi.fn(),
  success: vi.fn(),
  nico: vi.fn(),
  ask: vi.fn(),
  alert: vi.fn(),
}));
vi.mock('../useConversationHome', () => ({
  useConversationHome: () => mocks.home,
}));
vi.mock('vue-router', () => ({ useRouter: () => ({ push: mocks.push }) }));
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
        expose({ dialogRef: { open: mocks.open }, onSuccess: mocks.success });
      },
      template: '<div data-contact-dialog />',
    },
  })
);

describe('NICO conversation workspace', () => {
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

  it.each([false, true])(
    'keeps meaningful colored values and neutral unavailable data with dark=%s',
    dark => {
      document.documentElement.classList.toggle('dark', dark);
      wrapper = mount(ConversationHome);
      const cards = wrapper.findAll('article');
      expect(cards.map(card => card.get('strong').text())).toEqual([
        '3',
        '—',
        '2',
        '5',
      ]);
      expect(cards.map(card => card.get('strong').classes()[2])).toEqual([
        'text-n-blue-11',
        'text-n-slate-11',
        'text-n-amber-11',
        'text-n-violet-11',
      ]);
      expect(cards[1].text()).toContain('Indisponível');
      expect(cards[3].text()).toContain('Atividades pendentes');
      expect(wrapper.get('main').classes()).toContain('overflow-y-auto');
      expect(wrapper.findComponent(ConversationQuickActions).exists()).toBe(
        false
      );
      expect(wrapper.find('[data-contact-dialog]').exists()).toBe(false);
      expect(
        wrapper.get('button[type="submit"]').attributes('disabled')
      ).toBeDefined();
    }
  );

  it('uses the existing NICO panel for prompts and never fabricates results', async () => {
    wrapper = mount(ConversationHome);
    await wrapper.get('input').setValue('Resuma minhas conversas');
    await wrapper.get('form').trigger('submit');
    expect(mocks.ask).toHaveBeenCalledWith('Resuma minhas conversas');
    expect(wrapper.text()).not.toContain('Ação concluída');
    expect(wrapper.emitted('navigate')).toHaveLength(1);
  });

  it('drops drafts and remounts the contact dialog when account identity changes', async () => {
    wrapper = mount(ConversationHome);
    await wrapper.get('input').setValue('pedido da conta anterior');
    mocks.home.accountId.value = 2;
    await flushPromises();
    expect(wrapper.get('input').element.value).toBe('');
  });
});
