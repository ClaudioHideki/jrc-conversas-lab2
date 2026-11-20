import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ref } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import EndingReasonCatalog from './EndingReasonCatalog.vue';

vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { acwPolicy: vi.fn(), updateAcwPolicy: vi.fn(), queues: vi.fn() },
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
enableAutoUnmount(afterEach);
const Dialog = {
  emits: ['close'],
  setup(_props, { expose }) {
    const visible = ref(false);
    expose({
      open: () => {
        visible.value = true;
      },
    });
    return { visible };
  },
  template: '<section v-if="visible" role="dialog"><slot /></section>',
};
const entry = i => ({
  code: `synthetic_${i}`,
  name: `SYNTHETIC reason ${i}`,
  category: 'SYNTHETIC',
  description: '',
  order: i,
  active: i % 2 === 0,
});
const response = rows => ({
  data: {
    item: {
      id: '1',
      revision: 'a'.repeat(64),
      limits: { voice: 180, whatsapp: 180 },
      voice_reason_catalog: { version: rows.length ? 1 : 0, entries: rows },
    },
  },
});
const render = () =>
  mount(EndingReasonCatalog, {
    props: { accountId: '1' },
    global: { stubs: { Dialog } },
  });
beforeEach(() => {
  vi.clearAllMocks();
  API.acwPolicy.mockResolvedValue(response([]));
  API.queues.mockResolvedValue({ data: { items: [], meta: { pages: 0 } } });
});

describe('native ending reason catalogue dialog', () => {
  it('shows an authorized selected queue outside the current picker page and preserves unknown references without inventing names', async () => {
    const configured = response([entry(0)]);
    configured.data.item.voice_reason_catalog.required_queue_ids = [
      '950',
      '951',
    ];
    configured.data.item.voice_reason_queues = [
      { id: '950', name: 'SYNTHETIC selected native queue' },
    ];
    API.acwPolicy.mockResolvedValue(configured);
    const wrapper = render();
    await flushPromises();
    const selected = wrapper.findAll('[data-ending-selected-queue]');
    expect(selected).toHaveLength(2);
    expect(selected[0].text()).toContain('SYNTHETIC selected native queue');
    expect(selected[1].text()).toContain(
      'JRC_CONTACT_CENTER.ENDING_REASONS.QUEUE_ID'
    );
    expect(API.updateAcwPolicy).not.toHaveBeenCalled();
  });

  it('paginates a bounded catalogue and applies and clears the native name and status filters', async () => {
    API.acwPolicy.mockResolvedValue(
      response(Array.from({ length: 12 }, (_, i) => entry(i)))
    );
    const wrapper = render();
    await flushPromises();
    expect(wrapper.findAll('[data-ending-entry]')).toHaveLength(10);
    await wrapper.get('[data-ending-next]').trigger('click');
    expect(wrapper.findAll('[data-ending-entry]')).toHaveLength(2);
    await wrapper.get('[data-ending-search]').setValue('reason 11');
    expect(wrapper.findAll('[data-ending-entry]')).toHaveLength(1);
    await wrapper.get('[data-ending-status]').setValue('active');
    expect(wrapper.findAll('[data-ending-entry]')).toHaveLength(0);
    await wrapper.get('[data-ending-clear]').trigger('click');
    expect(wrapper.findAll('[data-ending-entry]')).toHaveLength(10);
  });

  it('preserves a saved code while allowing its name, category and active state to be edited', async () => {
    API.acwPolicy.mockResolvedValue(response([entry(0)]));
    const wrapper = render();
    await flushPromises();
    expect(
      wrapper.get('[data-ending-code]').attributes('disabled')
    ).toBeDefined();
    expect(
      wrapper.get('[data-ending-name]').attributes('disabled')
    ).toBeUndefined();
    await wrapper.get('[data-ending-active]').setValue(false);
    expect(
      wrapper.get('[data-ending-save]').attributes('disabled')
    ).toBeUndefined();
  });

  it('opens the page containing a new row and requires all mandatory fields before saving', async () => {
    API.acwPolicy.mockResolvedValue(
      response(Array.from({ length: 11 }, (_, i) => entry(i)))
    );
    const wrapper = render();
    await flushPromises();
    await wrapper.get('[data-ending-add]').trigger('click');
    await flushPromises();
    const fields = wrapper.findAll('[data-ending-code]');
    const code = fields.find(field => field.element.value === '');
    expect(code).toBeDefined();
    expect(code.attributes('disabled')).toBeUndefined();
    expect(
      wrapper.get('[data-ending-save]').attributes('disabled')
    ).toBeDefined();
    await code.setValue('synthetic_new');
    const last = wrapper.findAll('[data-ending-entry]').at(-1);
    await last.get('[data-ending-name]').setValue('SYNTHETIC new');
    await last.get('[data-ending-category]').setValue('SYNTHETIC');
    expect(
      wrapper.get('[data-ending-save]').attributes('disabled')
    ).toBeUndefined();
  });

  it('requires an explicit discard decision when closing with unsaved edits', async () => {
    const wrapper = render();
    await flushPromises();
    await wrapper.get('[data-ending-add]').trigger('click');
    await wrapper.get('[data-ending-close]').trigger('click');
    expect(wrapper.emitted('close')).toBeUndefined();
    expect(wrapper.find('[data-ending-discard]').exists()).toBe(true);
    await wrapper.get('[data-ending-discard-confirm]').trigger('click');
    expect(wrapper.emitted('close')).toHaveLength(1);
  });
  it('removes only an uncommitted new entry and keeps every saved code intact', async () => {
    API.acwPolicy.mockResolvedValue(response([entry(0)]));
    const wrapper = render();
    await flushPromises();
    expect(wrapper.find('[data-ending-remove-new]').exists()).toBe(false);
    await wrapper.get('[data-ending-add]').trigger('click');
    await flushPromises();
    expect(wrapper.findAll('[data-ending-entry]')).toHaveLength(2);
    await wrapper.get('[data-ending-remove-new]').trigger('click');
    expect(wrapper.findAll('[data-ending-entry]')).toHaveLength(1);
    expect(wrapper.get('[data-ending-code]').element.value).toBe('synthetic_0');
    expect(
      wrapper.get('[data-ending-code]').attributes('disabled')
    ).toBeDefined();
    expect(
      wrapper.get('[data-ending-save]').attributes('disabled')
    ).toBeDefined();
  });
});
