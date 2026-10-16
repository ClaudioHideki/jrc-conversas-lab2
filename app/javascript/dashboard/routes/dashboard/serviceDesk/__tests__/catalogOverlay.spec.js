import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { reactive, ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createStore } from 'vuex';
import messages from 'dashboard/i18n/locale/pt_BR/jrcServiceDesk.json';
import {
  configurationContext,
  configurationEnvelope,
  configurationReceipt,
  configurationRow,
} from './configurationCases';
const holder = vi.hoisted(() => ({
  session: null,
  list: vi.fn(),
  save: vi.fn(),
  receipt: vi.fn(),
  record: vi.fn(),
}));
vi.mock('../composables/useServiceDesk', () => ({
  useServiceDesk: () => holder.session,
}));
vi.mock('dashboard/api/serviceDeskConfiguration', () => ({ default: holder }));
import ConfigurationManager from '../components/ConfigurationManager.vue';
const Button = {
  props: ['label', 'disabled', 'type'],
  template:
    '<button :type="type" :disabled="disabled"><slot />{{ label }}</button>',
};
const ScopeBar = {
  emits: ['update:unitId'],
  template:
    "<button data-select-unit @click=\"$emit('update:unitId', '10')\">Select fixture unit</button>",
};
const Panel = { template: '<section><slot /></section>' };
const Input = {
  props: ['modelValue', 'label', 'disabled'],
  emits: ['update:modelValue'],
  template:
    '<label>{{ label }}<input :aria-label="label" :value="modelValue" :disabled="disabled" @input="$emit(\'update:modelValue\', $event.target.value)" /></label>',
};
const V2 = {
  props: ['modelValue'],
  emits: ['update:modelValue'],
  template:
    '<fieldset><select data-child-select><option>Native option</option></select><button type="button" data-child-popover data-popover-content>Child popup</button><input data-description :value="modelValue.description" @input="$emit(\'update:modelValue\', { ...modelValue, description: $event.target.value })" /></fieldset>',
};
const Pagination = {
  props: ['currentPage'],
  emits: ['update:currentPage'],
  template:
    '<button data-next-page @click="$emit(\'update:currentPage\', currentPage + 1)">{{ currentPage }}</button>',
};
let wrapper;
beforeEach(() => {
  [holder.list, holder.save, holder.receipt, holder.record].forEach(fn =>
    fn.mockReset()
  );
  holder.session = {
    accountId: ref('1'),
    state: reactive({ status: 'ready', context: configurationContext() }),
    revalidate: vi.fn(),
    retry: vi.fn(),
  };
  holder.list.mockImplementation(
    async (_account, _resource, _unit, params) => ({
      contract_version: 1,
      account_id: '1',
      unit_id: '10',
      resource: 'services',
      items: Array.from({ length: 20 }, (_, index) =>
        configurationRow('services', {
          id: String(20 + (params.page - 1) * 20 + index),
        })
      ),
      meta: { total: 50, page: params.page, per_page: 20 },
    })
  );
  holder.record.mockImplementation(async (_account, _resource, id) =>
    configurationEnvelope('services', {
      record: configurationRow('services', { id }),
    })
  );
  HTMLDialogElement.prototype.showModal = function showModal() {
    this.setAttribute('open', '');
  };
  HTMLDialogElement.prototype.close = function close() {
    this.removeAttribute('open');
  };
});
afterEach(() => {
  wrapper?.unmount();
  wrapper = null;
  document.body.innerHTML = '';
});
const render = async () => {
  wrapper = mount(ConfigurationManager, {
    attachTo: document.body,
    props: { resource: 'services' },
    global: {
      plugins: [
        createStore({ getters: { 'accounts/isRTL': () => false } }),
        createI18n({
          legacy: false,
          locale: 'pt_BR',
          messages: { pt_BR: messages },
        }),
      ],
      stubs: {
        Button,
        ScopeBar,
        Panel,
        Input,
        Select: true,
        Pagination,
        State: true,
        ConfigurationV2Fields: V2,
        BaseTable: { template: '<div><slot name="row" /></div>' },
        BaseTableRow: Panel,
        BaseTableCell: Panel,
      },
    },
  });
  await wrapper.get('[data-select-unit]').trigger('click');
  await flushPromises();
};
const press = async label => {
  await wrapper
    .findAll('button')
    .find(button => button.text() === label)
    .trigger('click');
  await flushPromises();
};
const editor = () => document.querySelector('dialog[open]');
const nameInput = () =>
  editor().querySelector(
    `input[aria-label="${messages.JRC_SERVICE_DESK.FIELDS.name}"]`
  );
const inputName = async value => {
  nameInput().value = value;
  nameInput().dispatchEvent(new Event('input', { bubbles: true }));
  await flushPromises();
};
const submit = async () => {
  editor()
    .querySelector('form')
    .dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
  await flushPromises();
};

describe('Service catalog uses the same editor in a native overlay', () => {
  it('opens the correct service over the retained list, with viewport containment and internal scroll', async () => {
    await render();
    await press(messages.JRC_SERVICE_DESK.CATALOG.edit_record);
    expect(editor()).not.toBeNull();
    expect(nameInput().value).toBe('Fixture catalogue');
    expect(editor().className).toContain('max-w-5xl');
    expect(editor().className).toContain('100dvh');
    expect(editor().querySelector('.overflow-y-auto')).not.toBeNull();
    expect(wrapper.text()).toContain('Fixture catalogue');
  });

  it('cancels without persisting and keeps page/filter context', async () => {
    await render();
    await wrapper
      .get(`input[aria-label="${messages.JRC_SERVICE_DESK.COMMON.search}"]`)
      .setValue('Fixture');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    await wrapper.get('[data-next-page]').trigger('click');
    await flushPromises();
    await press(messages.JRC_SERVICE_DESK.CATALOG.edit_record);
    await inputName('Unsaved change');
    const cancel = [...editor().querySelectorAll('button')].find(
      button => button.textContent === messages.JRC_SERVICE_DESK.COMMON.cancel
    );
    cancel.click();
    await flushPromises();
    expect(editor()).toBeNull();
    expect(holder.save).not.toHaveBeenCalled();
    expect(wrapper.get('[data-next-page]').text()).toBe('2');
    expect(
      wrapper.get(
        `input[aria-label="${messages.JRC_SERVICE_DESK.COMMON.search}"]`
      ).element.value
    ).toBe('Fixture');
    expect(holder.list.mock.calls.at(-1)[3]).toMatchObject({
      page: 2,
      q: 'Fixture',
    });
  });

  it('persists with audit/readback and updates only the row without losing pagination or refreshing', async () => {
    await render();
    await wrapper.get('[data-next-page]').trigger('click');
    await flushPromises();
    await press(messages.JRC_SERVICE_DESK.CATALOG.edit_record);
    await inputName('Changed service');
    const updated = configurationRow('services', {
      id: '40',
      name: 'Changed service',
      revision: 'b'.repeat(64),
    });
    holder.save.mockResolvedValue(
      configurationEnvelope('services', { record: updated, audit_id: '80' })
    );
    holder.receipt.mockResolvedValue(
      configurationReceipt('services', {
        action: 'update',
        record_id: '40',
        after: {
          ...configurationReceipt('services').receipt.after,
          name: updated.name,
        },
      })
    );
    holder.record.mockResolvedValue(
      configurationEnvelope('services', { record: updated })
    );
    const before = holder.list.mock.calls.length;
    await submit();
    expect(holder.save).toHaveBeenCalledOnce();
    expect(holder.receipt).toHaveBeenCalledOnce();
    expect(editor()).toBeNull();
    expect(wrapper.text()).toContain('Changed service');
    expect(wrapper.get('[data-next-page]').text()).toBe('2');
    expect(holder.list.mock.calls.length).toBe(before);
    expect(holder.session.revalidate).not.toHaveBeenCalled();
  });

  it('keeps values and dialog on validation error and prevents duplicate submission', async () => {
    await render();
    await press(messages.JRC_SERVICE_DESK.CATALOG.edit_record);
    await inputName('Keep this value');
    let reject;
    holder.save.mockImplementation(
      () =>
        new Promise((_resolve, failure) => {
          reject = failure;
        })
    );
    await submit();
    await submit();
    expect(holder.save).toHaveBeenCalledOnce();
    reject({ response: { status: 422 } });
    await flushPromises();
    expect(editor()).not.toBeNull();
    expect(nameInput().value).toBe('Keep this value');
    expect(editor().textContent).toContain(
      messages.JRC_SERVICE_DESK.ADMIN.feedback.invalid_request
    );
  });

  it('keeps the overlay open during a native select, popup and nested dialog events', async () => {
    await render();
    await press(messages.JRC_SERVICE_DESK.CATALOG.edit_record);
    const dialog = editor();
    dialog.querySelector('[data-child-select]').click();
    dialog.querySelector('[data-child-popover]').click();
    const child = document.createElement('dialog');
    dialog.appendChild(child);
    child.dispatchEvent(
      new Event('cancel', { bubbles: true, cancelable: true })
    );
    child.dispatchEvent(new Event('close', { bubbles: true }));
    await flushPromises();
    expect(editor()).toBe(dialog);
    expect(holder.save).not.toHaveBeenCalled();
    dialog.dispatchEvent(new Event('cancel', { cancelable: true }));
    await flushPromises();
    expect(editor()).toBeNull();
  });

  it('loads each selected record independently without keeping another service draft', async () => {
    await render();
    await press(messages.JRC_SERVICE_DESK.CATALOG.edit_record);
    await inputName('Discard me');
    editor().dispatchEvent(new Event('cancel', { cancelable: true }));
    await flushPromises();
    holder.record.mockResolvedValue(
      configurationEnvelope('services', {
        record: configurationRow('services', {
          id: '21',
          name: 'Second service',
          description: 'Another service description',
        }),
      })
    );
    await wrapper
      .findAll('button')
      .filter(
        button =>
          button.text() === messages.JRC_SERVICE_DESK.CATALOG.edit_record
      )[1]
      .trigger('click');
    await flushPromises();
    expect(holder.record.mock.calls.at(-1)[2]).toBe('21');
    expect(nameInput().value).toBe('Second service');
    expect(editor().querySelector('[data-description]').value).toBe(
      'Another service description'
    );
  });

  it('refuses a record response that belongs to a different service', async () => {
    await render();
    holder.record.mockResolvedValue(
      configurationEnvelope('services', {
        record: configurationRow('services', { id: '999' }),
      })
    );
    await press(messages.JRC_SERVICE_DESK.CATALOG.edit_record);
    expect(editor()).toBeNull();
    expect(holder.save).not.toHaveBeenCalled();
  });
});
