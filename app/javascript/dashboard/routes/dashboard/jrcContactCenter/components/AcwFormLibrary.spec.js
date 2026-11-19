import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import AcwFormLibrary from './AcwFormLibrary.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: {
    acwForms: vi.fn(),
    configurationRecord: vi.fn(),
    saveAcwForm: vi.fn(),
    acwFormHistory: vi.fn(),
    acwFormVersion: vi.fn(),
  },
}));
vi.mock('dashboard/components-next/dialog/Dialog.vue', () => ({
  default: {
    emits: ['close'],
    setup(_, { expose, emit }) {
      expose({ open: vi.fn(), close: () => emit('close') });
    },
    template: '<section><slot /><slot name="footer" /></section>',
  },
}));
enableAutoUnmount(afterEach);
const record = {
  id: '19',
  revision: 1,
  name: 'SYNTHETIC form',
  description: '',
  status: 'active',
  definition: {
    fields: [
      {
        key: 'detail',
        label: 'SYNTHETIC question',
        type: 'text',
        required: true,
      },
    ],
  },
};
const list = (page = 1) => ({
  data: {
    items: [{ ...record, definition: undefined }],
    meta: { total: 21, page, pages: 2 },
  },
});
beforeEach(() => {
  vi.clearAllMocks();
  API.acwForms.mockResolvedValue(list());
  API.configurationRecord.mockResolvedValue({
    data: { item: structuredClone(record) },
  });
  API.saveAcwForm.mockResolvedValue({
    data: { item: { ...record, revision: 2 } },
  });
  API.acwFormHistory.mockResolvedValue({
    data: {
      items: [{ ...record, definition: undefined }],
      meta: { page: 1, pages: 1 },
    },
  });
  API.acwFormVersion.mockResolvedValue({
    data: { item: structuredClone(record) },
  });
});
const library = () => mount(AcwFormLibrary, { props: { accountId: '1' } });

describe('native ACW form management dialog', () => {
  it('loads a bounded native list with active status and no write on opening', async () => {
    const wrapper = library();
    await flushPromises();
    expect(API.acwForms).toHaveBeenCalledWith('1', {
      q: '',
      status: 'active',
      page: 1,
      per_page: 20,
    });
    expect(wrapper.findAll('[data-acw-form-row]')).toHaveLength(1);
    expect(API.saveAcwForm).not.toHaveBeenCalled();
  });

  it('keeps submitted search and status filters when fetching the next page', async () => {
    const wrapper = library();
    await flushPromises();
    await wrapper.get('[data-acw-form-search]').setValue('SYNTHETIC search');
    await wrapper.get('[data-acw-form-status]').setValue('archived');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    const next = wrapper
      .findAll('button')
      .find(button => button.text().endsWith('LOCAL_IVR.NEXT'));
    await next.trigger('click');
    await flushPromises();
    expect(API.acwForms).toHaveBeenLastCalledWith('1', {
      q: 'SYNTHETIC search',
      status: 'archived',
      page: 2,
      per_page: 20,
    });
  });

  it('requires explicit discard before closing a changed form and never saves on close', async () => {
    const wrapper = library();
    await flushPromises();
    await wrapper.get('[data-acw-form-open]').trigger('click');
    await flushPromises();
    await wrapper.get('[data-acw-form-name]').setValue('SYNTHETIC unsaved');
    const close = wrapper
      .findAll('button')
      .find(button => button.text().endsWith('LOCAL_IVR.CLOSE'));
    await close.trigger('click');
    expect(wrapper.emitted('close')).toBeUndefined();
    expect(wrapper.get('[data-acw-form-confirmation]').text()).toContain(
      'CONFIRM_DISCARD'
    );
    await wrapper.get('[data-acw-form-confirm]').trigger('click');
    expect(wrapper.emitted('close')).toHaveLength(1);
    expect(API.saveAcwForm).not.toHaveBeenCalled();
  });

  it('blocks unload while a changed form exists and removes its listener on unmount', async () => {
    const wrapper = library();
    await flushPromises();
    await wrapper.get('[data-acw-form-open]').trigger('click');
    await flushPromises();
    await wrapper.get('[data-acw-form-name]').setValue('SYNTHETIC retained');
    const pending = new Event('beforeunload', { cancelable: true });
    window.dispatchEvent(pending);
    expect(pending.defaultPrevented).toBe(true);
    wrapper.unmount();
    const removed = new Event('beforeunload', { cancelable: true });
    window.dispatchEvent(removed);
    expect(removed.defaultPrevented).toBe(false);
  });

  it('opens the original immutable history without replacing the current editor draft', async () => {
    const wrapper = library();
    await flushPromises();
    await wrapper.get('[data-acw-form-open]').trigger('click');
    await flushPromises();
    await wrapper.get('[data-acw-form-name]').setValue('SYNTHETIC local');
    await wrapper.get('[data-acw-form-history]').trigger('click');
    await flushPromises();
    expect(API.acwFormHistory).toHaveBeenCalledWith('1', '19', 1);
    const openVersion = wrapper
      .findAll('button')
      .find(button => button.text().endsWith('ACW_FORMS.OPEN'));
    await openVersion.trigger('click');
    await flushPromises();
    expect(API.acwFormVersion).toHaveBeenCalledWith('1', '19', 1);
    expect(
      wrapper.get('[data-acw-form-fields]').attributes('disabled')
    ).toBeDefined();
    expect(API.saveAcwForm).not.toHaveBeenCalled();
  });

  it('does not automatically retry a failed list request or submit a form while authority is unknown', async () => {
    API.acwForms.mockRejectedValueOnce(new Error('synthetic failure'));
    const wrapper = library();
    await flushPromises();
    expect(wrapper.get('[role="alert"]').text()).toContain('ERROR');
    expect(
      wrapper.get('[data-acw-form-new]').attributes('disabled')
    ).toBeDefined();
    expect(API.acwForms).toHaveBeenCalledTimes(1);
    expect(API.saveAcwForm).not.toHaveBeenCalled();
  });
});

describe('Existing library exact operational version selection', () => {
  it('does not expose selection in the original manager-only mode', async () => {
    const wrapper = library();
    await flushPromises();
    expect(wrapper.find('[data-acw-form-select]').exists()).toBe(false);
    expect(API.configurationRecord).not.toHaveBeenCalled();
  });
  it('resolves the selected latest version and emits only the operational definition', async () => {
    const wrapper = mount(AcwFormLibrary, {
      props: { accountId: '1', allowSelection: true },
    });
    await flushPromises();
    await wrapper.get('[data-acw-form-select]').trigger('click');
    await flushPromises();
    expect(API.configurationRecord).toHaveBeenCalledWith(
      '1',
      'acw_forms',
      '19'
    );
    expect(wrapper.emitted('select')[0]).toEqual([
      {
        id: record.id,
        revision: record.revision,
        name: record.name,
        definition: record.definition,
      },
    ]);
    expect(API.saveAcwForm).not.toHaveBeenCalled();
  });
  it('rejects a catalogue revision changed between list and selection without silently choosing the new version', async () => {
    API.configurationRecord.mockResolvedValueOnce({
      data: { item: { ...record, revision: 2 } },
    });
    const wrapper = mount(AcwFormLibrary, {
      props: { accountId: '1', allowSelection: true },
    });
    await flushPromises();
    await wrapper.get('[data-acw-form-select]').trigger('click');
    await flushPromises();
    expect(wrapper.emitted('select')).toBeUndefined();
    expect(wrapper.find('[role="alert"]').exists()).toBe(true);
    expect(API.saveAcwForm).not.toHaveBeenCalled();
  });
  it('does not offer archived rows as new bindings', async () => {
    API.acwForms.mockResolvedValueOnce({
      data: {
        items: [{ ...record, status: 'archived' }],
        meta: { page: 1, pages: 1, total: 1 },
      },
    });
    const wrapper = mount(AcwFormLibrary, {
      props: { accountId: '1', allowSelection: true },
    });
    await flushPromises();
    expect(wrapper.find('[data-acw-form-select]').exists()).toBe(false);
    expect(API.configurationRecord).not.toHaveBeenCalled();
  });
});
