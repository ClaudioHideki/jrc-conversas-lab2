import { describe, it, expect, vi } from 'vitest';
import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import StructureView from '../views/StructureView.vue';
import messages from 'dashboard/i18n/locale/en/jrcServiceDesk.json';
const state = vi.hoisted(() => ({ visible: false, context: null, status: 'denied' }));
vi.mock('vue-router', () => ({ useRoute: () => ({ params: { accountId: '1' } }), useRouter: () => ({ push: vi.fn() }) }));
vi.mock('dashboard/composables/store', () => ({ useStore: () => ({ getters: { getCurrentUserID: '10', 'accounts/isFeatureEnabledonAccount': () => true } }) }));
vi.mock('dashboard/composables/useServiceDeskStructure', () => ({ useServiceDeskStructure: () => ({ state, refresh: vi.fn() }) }));
vi.mock('dashboard/api/serviceDeskStructure', () => ({ default: { context: vi.fn(), list: vi.fn() } }));
describe('CP6-D01 structural page denial', () => {
  it('does not render or submit a grant form when the native structural context is denied', () => {
    const wrapper = mount(StructureView, { global: { plugins: [createI18n({ legacy: false, locale: 'en', messages: { en: messages } })] } });
    expect(wrapper.find('form').exists()).toBe(false);
    expect(wrapper.text()).toContain('No structural authority');
    wrapper.unmount();
  });
});
