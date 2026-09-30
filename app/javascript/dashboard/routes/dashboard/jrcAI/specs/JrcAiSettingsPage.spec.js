import { mount, flushPromises } from '@vue/test-utils';
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
    vi.restoreAllMocks();
  });

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
});
