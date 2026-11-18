import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcContactCenter';
import messages from 'dashboard/i18n/locale/en/jrcContactCenter.json';
import IvrReferencePicker from './IvrReferencePicker.vue';

vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { units: vi.fn(), queues: vi.fn(), ivrReference: vi.fn() },
}));
const mountPicker = props =>
  mount(IvrReferencePicker, {
    props: {
      accountId: '1',
      resource: 'units',
      inputId: 'synthetic-reference',
      modelValue: '',
      ...props,
    },
    global: {
      plugins: [
        createI18n({ legacy: false, locale: 'en', messages: { en: messages } }),
      ],
    },
  });
enableAutoUnmount(afterEach);
beforeEach(() => {
  vi.clearAllMocks();
  API.units.mockResolvedValue({
    data: {
      items: [{ id: 7, name: 'SYNTHETIC unit', code: 'OWN', status: 'active' }],
      meta: { pages: 2 },
    },
  });
  API.queues.mockResolvedValue({ data: { items: [], meta: { pages: 0 } } });
  API.ivrReference.mockResolvedValue({
    data: {
      item: {
        id: 7,
        name: 'SYNTHETIC selected',
        code: 'SELECTED',
        status: 'active',
      },
    },
  });
});

describe('native scoped IVR references', () => {
  it('uses bounded native pagination and resets the page on an explicit search', async () => {
    const wrapper = mountPicker();
    await flushPromises();
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'Próxima')
      .trigger('click');
    await flushPromises();
    expect(API.units).toHaveBeenLastCalledWith('1', {
      page: 2,
      per_page: 20,
      q: '',
      status: 'active',
    });
    await wrapper.get('input[type=search]').setValue('SYNTHETIC query');
    await wrapper.get('input[type=search]').trigger('keydown.enter');
    await flushPromises();
    expect(API.units).toHaveBeenLastCalledWith('1', {
      page: 1,
      per_page: 20,
      q: 'SYNTHETIC query',
      status: 'active',
    });
  });

  it('loads an authorized selected reference outside the current page and keeps locked identity readable', async () => {
    API.ivrReference.mockResolvedValueOnce({
      data: {
        item: {
          id: 900,
          name: 'SYNTHETIC saved unit',
          code: 'SAVED',
          status: 'inactive',
        },
      },
    });
    const wrapper = mountPicker({ modelValue: '900', disabled: true });
    await flushPromises();
    expect(API.ivrReference).toHaveBeenLastCalledWith('1', 'units', '900');
    expect(wrapper.get('select').element.disabled).toBe(true);
    expect(wrapper.text()).toContain('SYNTHETIC saved unit');
    expect(wrapper.text()).toContain('inativo');
  });

  it('does not offer another channel as a voice destination', async () => {
    API.queues.mockResolvedValue({
      data: {
        items: [
          {
            id: 1,
            unit_id: 7,
            name: 'SYNTHETIC voice',
            code: 'VOICE',
            service_kind: 'voice',
          },
          {
            id: 2,
            unit_id: 7,
            name: 'SYNTHETIC chat',
            code: 'CHAT',
            service_kind: 'whatsapp',
          },
        ],
        meta: { pages: 1 },
      },
    });
    const wrapper = mountPicker({ resource: 'queues', unitId: '7' });
    await flushPromises();
    expect(wrapper.get('option[value="1"]').element.disabled).toBe(false);
    expect(wrapper.get('option[value="2"]').element.disabled).toBe(true);
    expect(API.queues).toHaveBeenCalledWith(
      '1',
      expect.objectContaining({ unit_id: '7' })
    );
  });

  it('rejects a late selected queue whose unit differs from the current context', async () => {
    let finish;
    API.ivrReference.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const wrapper = mountPicker({
      resource: 'queues',
      unitId: '7',
      modelValue: '55',
    });
    API.ivrReference.mockResolvedValueOnce({
      data: {
        item: { id: 55, unit_id: 7, name: 'PRIVATE old unit', code: 'OLD' },
      },
    });
    await wrapper.setProps({ unitId: '8' });
    finish({
      data: {
        item: {
          id: 55,
          unit_id: 7,
          name: 'PRIVATE late response',
          code: 'OLD',
        },
      },
    });
    await flushPromises();
    expect(wrapper.text()).not.toContain('PRIVATE');
    expect(wrapper.find('[role=alert]').exists()).toBe(true);
  });

  it('clears unavailable rows after a native authorization failure', async () => {
    const wrapper = mountPicker();
    await flushPromises();
    API.units.mockRejectedValueOnce({ response: { status: 401 } });
    await wrapper.get('input[type=search]').trigger('keydown.enter');
    await flushPromises();
    expect(wrapper.find('option[value="7"]').exists()).toBe(false);
    expect(wrapper.get('select').element.disabled).toBe(true);
  });

  it('does not retain a loading spinner or make an unscoped query when the selected queue unit is cleared', async () => {
    let finish;
    API.queues.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const wrapper = mountPicker({ resource: 'queues', unitId: '7' });
    await wrapper.setProps({ unitId: '' });
    finish({
      data: {
        items: [{ id: 55, name: 'PRIVATE prior unit' }],
        meta: { pages: 1 },
      },
    });
    await flushPromises();
    expect(wrapper.text()).not.toContain('PRIVATE');
    expect(wrapper.get('select').element.disabled).toBe(true);
    expect(API.queues).toHaveBeenCalledOnce();
    expect(wrapper.find('[role=status]').exists()).toBe(false);
  });
});
