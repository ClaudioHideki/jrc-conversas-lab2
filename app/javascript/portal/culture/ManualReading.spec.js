import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { afterEach, describe, expect, it, vi } from 'vitest';
import ManualReading from './ManualReading.vue';
import messages from './pt_BR.json';

const base = '/portal/manual-de-cultura/api/accounts/7';
const current = {
  id: 19,
  grant_id: 8,
  title: 'Manual atual',
  number: 2,
  unit: 'Unidade',
  current: true,
  confirmed_at: null,
  files: [{ kind: 'pdf' }, { kind: 'pptx' }],
};
const previous = {
  ...current,
  id: 18,
  title: 'Manual anterior',
  number: 1,
  current: false,
  confirmed_at: '2026-11-23T13:00:00Z',
};

const button = (wrapper, label) =>
  wrapper.findAll('button').find(item => item.text() === label);

const render = props =>
  mount(ManualReading, {
    props: { base, entries: [current, previous], ...props },
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

afterEach(() => vi.unstubAllGlobals());

describe('Manual de Cultura reader', () => {
  it('posts the shown version and bound grant once and confirms the persisted response', async () => {
    let finish;
    const fetcher = vi.fn(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    vi.stubGlobal('fetch', fetcher);
    const wrapper = render();
    await button(wrapper, 'Ler o manual').trigger('click');
    expect(wrapper.find('iframe').attributes('src')).toBe(
      `${base}/versions/19/files/pdf`
    );
    const confirm = button(wrapper, 'Li e estou ciente');
    await confirm.trigger('click');
    expect(confirm.attributes('disabled')).toBeDefined();
    await confirm.trigger('click');
    expect(fetcher).toHaveBeenCalledTimes(1);
    expect(fetcher).toHaveBeenCalledWith(
      `${base}/versions/19/confirm`,
      expect.objectContaining({
        method: 'POST',
        body: JSON.stringify({ grant_id: 8 }),
        credentials: 'same-origin',
      })
    );
    finish({
      ok: true,
      status: 200,
      json: async () => ({
        ...current,
        confirmed_at: '2026-11-23T13:00:00Z',
      }),
    });
    await flushPromises();
    expect(wrapper.text()).toContain('Ciência registrada com sucesso.');
    expect(wrapper.emitted('changed')).toHaveLength(1);
  });

  it('lets the employee open a preserved version without offering a new confirmation', async () => {
    const wrapper = render({ history: true });
    expect(wrapper.text()).toContain('Manual anterior');
    await wrapper.findAll('button').at(-1).trigger('click');
    expect(wrapper.find('iframe').attributes('src')).toBe(
      `${base}/versions/18/files/pdf`
    );
    expect(button(wrapper, 'Li e estou ciente')).toBeUndefined();
  });

  it('keeps the selected manual visible when it is superseded during confirmation', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue({
        ok: false,
        status: 409,
        json: async () => ({ code: 'version_unavailable' }),
      })
    );
    const wrapper = render();
    await button(wrapper, 'Ler o manual').trigger('click');
    await button(wrapper, 'Li e estou ciente').trigger('click');
    await flushPromises();
    expect(wrapper.find('[role="alert"]').text()).toContain('substituída');
    expect(wrapper.emitted('changed')).toBeUndefined();
    expect(wrapper.find('iframe').attributes('src')).toContain('/versions/19/');
  });
});
