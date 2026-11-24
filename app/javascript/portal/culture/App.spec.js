import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { afterEach, describe, expect, it, vi } from 'vitest';
import App from './App.vue';
import messages from './pt_BR.json';

const portal = '/portal/manual-de-cultura';
const allowed = {
  accounts: [
    { id: 1, name: 'GRUPO JRC', administrator: false, employee: true },
  ],
};

function response(status, data = {}) {
  return { ok: status === 200, status, json: async () => data };
}

function render() {
  return mount(App, {
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale: 'pt_BR',
          messages: { pt_BR: messages },
        }),
      ],
    },
  });
}

afterEach(() => vi.unstubAllGlobals());

describe('Manual de Cultura session entry', () => {
  it('opens the manual with the authorized JRC dashboard session without submitting a password', async () => {
    const fetcher = vi
      .fn()
      .mockResolvedValueOnce(response(200, allowed))
      .mockResolvedValueOnce(response(200, { entries: [] }));
    vi.stubGlobal('fetch', fetcher);

    const wrapper = render();
    await flushPromises();

    expect(fetcher.mock.calls.map(([url]) => url)).toEqual([
      `${portal}/session`,
      `${portal}/api/accounts/1/manuals`,
    ]);
    expect(wrapper.find('input[type="password"]').exists()).toBe(false);
    expect(wrapper.text()).toContain('Minha ciência');
    wrapper.unmount();
  });

  it('explains a permission denial and rechecks access without demanding credentials', async () => {
    const fetcher = vi
      .fn()
      .mockResolvedValueOnce(response(403))
      .mockResolvedValueOnce(response(200, allowed))
      .mockResolvedValueOnce(response(200, { entries: [] }));
    vi.stubGlobal('fetch', fetcher);

    const wrapper = render();
    await flushPromises();
    expect(wrapper.text()).toContain('Você está conectado ao JRC');
    expect(wrapper.find('input[type="password"]').exists()).toBe(false);

    const retry = wrapper
      .findAll('button')
      .find(button => button.text() === 'Tentar novamente');
    await retry.trigger('click');
    await flushPromises();

    expect(fetcher).toHaveBeenCalledTimes(3);
    expect(wrapper.text()).toContain('Minha ciência');
    wrapper.unmount();
  });

  it('offers the native login when the user opens the direct link without a session', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(response(401)));
    const wrapper = render();
    await flushPromises();
    expect(wrapper.find('input[type="password"]').exists()).toBe(true);
    expect(wrapper.text()).toContain('Entrar com minha conta JRC');
    wrapper.unmount();
  });
});
