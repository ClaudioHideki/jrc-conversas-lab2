import { mount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import JrcAiAgentsPage from '../JrcAiAgentsPage.vue';
import api from 'dashboard/api/jrcAi';
import { useRouter } from 'vue-router';

const { close, push } = vi.hoisted(() => ({ close: vi.fn(), push: vi.fn() }));
vi.mock('vue-router', () => ({
  useRouter: () => ({ push }),
  useRoute: () => ({ params: { accountId: '1' } }),
}));

let allowed;
vi.mock('dashboard/composables/usePolicy', () => ({
  usePolicy: () => ({ checkPermissions: () => allowed.value }),
}));
vi.mock('dashboard/api/jrcAi', () => ({ default: { agents: vi.fn() } }));
vi.mock('dashboard/components-next/jrcCopilot/useJrcCopilot', () => ({
  useJrcCopilot: () => ({ close }),
}));

describe('AI specialist navigation', () => {
  let wrapper;
  beforeEach(() => {
    allowed = ref(false);
    api.agents.mockResolvedValue({
      data: {
        agents: [{ key: 'commercial', name: 'Comercial', status: 'ready' }],
        profile: 'agent',
      },
    });
  });
  afterEach(() => {
    wrapper?.unmount();
    sessionStorage.clear();
  });

  it('only exposes provider configuration to administrators', async () => {
    wrapper = mount(JrcAiAgentsPage);
    await flushPromises();
    expect(wrapper.text()).not.toContain('Configurar provedores');
    allowed.value = true;
    await flushPromises();
    expect(wrapper.text()).toContain('Configurar provedores');
  });

  it('selects the specialist and returns to conversations', async () => {
    wrapper = mount(JrcAiAgentsPage);
    await flushPromises();
    await wrapper.find('article button').trigger('click');
    expect(sessionStorage.getItem('jrcNicoPreferredAgent')).toBe('commercial');
    expect(close).toHaveBeenCalledOnce();
    expect(useRouter().push).toHaveBeenCalledWith(
      expect.objectContaining({ name: 'home' })
    );
  });

  it('cannot select a restricted specialist', async () => {
    api.agents.mockResolvedValue({
      data: { agents: [{ key: 'commercial', status: 'restricted' }] },
    });
    wrapper = mount(JrcAiAgentsPage);
    await flushPromises();
    expect(wrapper.find('article button').attributes('disabled')).toBeDefined();
    await wrapper.find('article button').trigger('click');
    expect(sessionStorage.getItem('jrcNicoPreferredAgent')).toBeNull();
  });
});
