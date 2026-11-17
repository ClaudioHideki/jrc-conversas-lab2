import { afterEach, expect, it, vi } from 'vitest';
import { defineComponent } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import { createMemoryHistory, createRouter } from 'vue-router';
import AdministrationSection from './AdministrationSection.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: {
    administrativeList: vi.fn().mockResolvedValue({ data: { items: [] } }),
  },
}));
enableAutoUnmount(afterEach);
const prepare = async permitted => {
  const target = defineComponent({
    template: '<div>SYNTHETIC native route target</div>',
  });
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: '/control-desk', component: target },
      {
        path: '/app/accounts/:accountId/ramal/configuracao',
        name: 'ramal_settings',
        component: target,
      },
    ],
  });
  await router.push('/control-desk');
  await router.isReady();
  const wrapper = mount(AdministrationSection, {
    props: {
      accountId: '1',
      card: { key: 'pabx', state: 'read_only' },
      context: { capabilities: {}, native_links: { pabx_settings: permitted } },
    },
    global: { plugins: [router], stubs: { Dialog: true } },
  });
  await flushPromises();
  return { wrapper, router };
};

it('keeps native infrastructure navigation unavailable without the server capability', async () => {
  const { wrapper } = await prepare(false);
  expect(wrapper.find('[data-native-pabx-settings]').exists()).toBe(false);
});

it('navigates through the native router with the current account instead of duplicating settings', async () => {
  const { wrapper, router } = await prepare(true);
  await wrapper.get('[data-native-pabx-settings]').trigger('click');
  await flushPromises();
  expect(router.currentRoute.value.name).toBe('ramal_settings');
  expect(router.currentRoute.value.params.accountId).toBe('1');
});
