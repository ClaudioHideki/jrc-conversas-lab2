import { describe, expect, it, vi } from 'vitest';
import { defineComponent } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { createRouter, createMemoryHistory } from 'vue-router';
import { createStore } from 'vuex';
import { routeIsAccessibleFor } from 'dashboard/helper/routeHelpers';
import { routes } from './routes';
import SipSettingsRoute from './SipSettingsRoute.vue';

vi.mock('./SipSettingsPage.vue', () => ({
  default: {
    name: 'NativeSipSettingsPage',
    data: () => ({ draft: '' }),
    template: '<input data-native-draft v-model="draft" />',
  },
}));

const Host = defineComponent({ template: '<RouterView />' });

describe('native SIP settings context boundary', () => {
  it('destroys the old form when switching accounts rather than reusing credentials or unsaved values', async () => {
    const router = createRouter({
      history: createMemoryHistory(),
      routes: [
        {
          path: '/app/accounts/:accountId/ramal/configuracao',
          component: SipSettingsRoute,
        },
      ],
    });
    const store = createStore({
      getters: { getCurrentUser: () => ({ id: 1, type: 'SuperAdmin' }) },
    });
    await router.push('/app/accounts/1/ramal/configuracao');
    await router.isReady();
    const wrapper = mount(Host, { global: { plugins: [router, store] } });
    await wrapper
      .get('[data-native-draft]')
      .setValue('SYNTHETIC account one draft');
    await router.push('/app/accounts/2/ramal/configuracao');
    await flushPromises();
    expect(wrapper.get('[data-native-draft]').element.value).toBe('');
    wrapper.unmount();
  });

  it('destroys the old form when the authenticated user or infrastructure profile changes', async () => {
    const router = createRouter({
      history: createMemoryHistory(),
      routes: [
        {
          path: '/app/accounts/:accountId/ramal/configuracao',
          component: SipSettingsRoute,
        },
      ],
    });
    const store = createStore({
      state: { user: { id: 1, type: 'SuperAdmin' } },
      getters: { getCurrentUser: state => state.user },
      mutations: {
        replace: (state, user) => {
          state.user = user;
        },
      },
    });
    await router.push('/app/accounts/1/ramal/configuracao');
    await router.isReady();
    const wrapper = mount(Host, { global: { plugins: [router, store] } });
    await wrapper.get('[data-native-draft]').setValue('SYNTHETIC old profile');
    store.commit('replace', { id: 1, type: 'User' });
    await flushPromises();
    expect(wrapper.get('[data-native-draft]').element.value).toBe('');
    await wrapper.get('[data-native-draft]').setValue('SYNTHETIC second user');
    store.commit('replace', { id: 2, type: 'User' });
    await flushPromises();
    expect(wrapper.get('[data-native-draft]').element.value).toBe('');
    wrapper.unmount();
  });

  it('accepts the existing explicit CC administration route entry without granting infrastructure authority to viewers', () => {
    const settings = routes.find(route => route.name === 'ramal_settings');
    expect(
      routeIsAccessibleFor(settings, [
        'custom_role',
        'jrc_contact_center_administer',
      ])
    ).toBe(true);
    expect(
      routeIsAccessibleFor(settings, ['custom_role', 'jrc_contact_center_view'])
    ).toBe(false);
    expect(routeIsAccessibleFor(settings, ['agent'])).toBe(false);
  });
});
