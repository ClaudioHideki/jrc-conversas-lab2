import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import { createMemoryHistory, createRouter } from 'vue-router';
import BackButton from './BackButton.vue';

const Page = { render: () => null };
let router;
enableAutoUnmount(afterEach);

beforeEach(async () => {
  router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: '/origin', name: 'origin', component: Page },
      { path: '/current', name: 'current', component: Page },
      { path: '/target/:id', name: 'target', component: Page },
    ],
  });
  await router.push('/origin');
  await router.isReady();
  await router.push('/current');
});

describe('BackButton router ownership', () => {
  it.each([
    { target: '/target/7', expected: '/target/7' },
    {
      target: { name: 'target', params: { id: '9' } },
      expected: '/target/9',
    },
  ])('uses the mounted router for $expected', async ({ target, expected }) => {
    const wrapper = mount(BackButton, {
      props: { backUrl: target, buttonLabel: 'Back' },
      global: { plugins: [router] },
    });
    await wrapper.get('button').trigger('click');
    await flushPromises();
    expect(router.currentRoute.value.fullPath).toBe(expected);
  });

  it('returns to the previous entry without an explicit destination', async () => {
    const wrapper = mount(BackButton, {
      props: { buttonLabel: 'Back' },
      global: { plugins: [router] },
    });
    await wrapper.get('button').trigger('click');
    await vi.waitFor(() => {
      expect(router.currentRoute.value.fullPath).toBe('/origin');
    });
  });
});
