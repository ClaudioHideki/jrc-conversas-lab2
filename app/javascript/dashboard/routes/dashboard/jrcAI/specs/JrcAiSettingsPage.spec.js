import { config, mount, flushPromises } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import ptBR from 'dashboard/i18n/locale/pt_BR';
import { ref } from 'vue';
import JrcAiSettingsPage from '../JrcAiSettingsPage.vue';
import api from 'dashboard/api/jrcAi';
import { useAlert } from 'dashboard/composables';

let role;
vi.mock('dashboard/composables/store', () => ({ useMapGetter: () => role }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/jrcAi', () => ({
  default: {
    providers: vi.fn(),
    usage: vi.fn(),
    makeDefault: vi.fn(),
    deleteProvider: vi.fn(),
  },
}));

describe('AI provider actions', () => {
  let wrapper;
  const originalPlugins = config.global.plugins;
  beforeEach(() => {
    role = ref('administrator');
    api.providers.mockResolvedValue({
      data: [{ id: 7, name: 'Local test', status: 'configured' }],
    });
    api.usage.mockResolvedValue({
      data: { totals: {}, by_agent: [], by_model: [], by_user: [], recent: [] },
    });
    vi.spyOn(window, 'confirm').mockReturnValue(true);
  });
  afterEach(() => {
    wrapper?.unmount();
    config.global.plugins = originalPlugins;
    document.documentElement.classList.remove('dark');
    vi.restoreAllMocks();
  });

  it.each([false, true])(
    'keeps localized labels and the hero foreground with dark=%s',
    async dark => {
      document.documentElement.classList.toggle('dark', dark);
      config.global.plugins = [
        createI18n({
          legacy: false,
          locale: 'pt_BR',
          messages: { pt_BR: ptBR },
        }),
      ];
      api.providers.mockResolvedValueOnce({
        data: [
          {
            id: 7,
            name: 'Teste',
            status: 'configured',
            masked_api_key: '••••1234',
          },
        ],
      });
      wrapper = mount(JrcAiSettingsPage);
      await flushPromises();
      expect(wrapper.get('header').classes()).toContain('text-white');
      expect(wrapper.get('header h1').classes()).toContain('text-inherit');
      expect(wrapper.get('header p').classes()).toContain('text-blue-50/90');
      expect(wrapper.text()).toContain('Chave da API');
      expect(wrapper.text()).toContain('••••1234');
      expect(wrapper.text()).not.toContain('API Key');
      await wrapper
        .findAll('button')
        .find(button => button.text() === 'Novo provedor')
        .trigger('click');
      expect(wrapper.get('form').text()).toContain('Chave da API');
      expect(wrapper.get('form input[type="password"]').element.value).toBe('');
    }
  );

  it.each([
    ['Definir como padrão', 'makeDefault'],
    ['Excluir', 'deleteProvider'],
  ])(
    'reports a failed %s without pretending success or losing the provider',
    async (label, method) => {
      api[method].mockRejectedValueOnce(new Error('test failure'));
      wrapper = mount(JrcAiSettingsPage);
      await flushPromises();
      await wrapper
        .findAll('button')
        .find(button => button.text() === label)
        .trigger('click');
      await flushPromises();
      expect(api[method]).toHaveBeenCalledExactlyOnceWith(7);
      expect(useAlert).toHaveBeenCalledOnce();
      expect(useAlert.mock.calls[0][0]).not.toMatch(/atualizado|removido/);
      expect(wrapper.text()).toContain('Local test');
    }
  );

  it('does not query administrative providers for an agent', async () => {
    role.value = 'agent';
    wrapper = mount(JrcAiSettingsPage);
    await flushPromises();
    expect(api.providers).not.toHaveBeenCalled();
    expect(api.usage).not.toHaveBeenCalled();
    expect(wrapper.text()).toContain('Acesso administrativo');
  });

  it('does not delete when confirmation is cancelled', async () => {
    window.confirm.mockReturnValue(false);
    wrapper = mount(JrcAiSettingsPage);
    await flushPromises();
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'Excluir')
      .trigger('click');
    expect(api.deleteProvider).not.toHaveBeenCalled();
  });

  it('keeps the provider dialog scrollable and closes it without saving', async () => {
    wrapper = mount(JrcAiSettingsPage);
    await flushPromises();
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'Novo provedor')
      .trigger('click');
    const form = wrapper.get('form');
    expect(form.classes()).toContain('overflow-y-auto');
    expect(form.classes()).toContain('overscroll-contain');
    expect(form.classes()).toContain('max-h-[calc(100dvh-2rem)]');
    expect(form.classes()).toContain('bg-n-solid-2');
    expect(form.get('input[type="password"]').classes()).toContain(
      'text-n-slate-12'
    );
    await form.get('button[aria-label="Close"]').trigger('click');
    expect(wrapper.find('form').exists()).toBe(false);
  });
});
