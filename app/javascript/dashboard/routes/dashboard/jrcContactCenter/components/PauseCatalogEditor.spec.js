import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ref, reactive } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import PauseCatalogEditor from './PauseCatalogEditor.vue';

const mocks = vi.hoisted(() => ({ route: null, replace: vi.fn() }));
vi.mock('vue-router', () => ({
  useRoute: () => mocks.route,
  useRouter: () => ({ replace: mocks.replace }),
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { pauseCatalog: vi.fn(), updatePauseCatalog: vi.fn() },
}));
const copy = key => `JRC_CONTACT_CENTER.PAUSE_CATALOG.${key}`;
const definition = {
  code: 'synthetic_break',
  name: 'SYNTHETIC saved pause',
  category: 'SYNTHETIC',
  description: '',
  active: true,
  minimum_minutes: 15,
  default_minutes: 30,
  maximum_minutes: 60,
  unit_ids: [],
  custom_role_ids: [],
};
const snapshot = (
  entries = [definition],
  id = '1',
  revision = 'a'.repeat(64)
) => ({ id, revision, version: 1, enforced: false, entries });
const Dialog = {
  name: 'Dialog',
  props: [
    'title',
    'disableConfirmButton',
    'confirmButtonLabel',
    'cancelButtonLabel',
  ],
  emits: ['confirm', 'close'],
  setup(_props, { emit, expose }) {
    const visible = ref(false);
    const close = () => {
      visible.value = false;
      emit('close');
    };
    expose({
      open: () => {
        visible.value = true;
      },
      close,
    });
    return { visible, close };
  },
  template: `<section v-if="visible" role="dialog"><h2>{{ title }}</h2><slot/><button data-confirm :disabled="disableConfirmButton" @click="$emit('confirm')">{{ confirmButtonLabel }}</button><button data-cancel @click="close">{{ cancelButtonLabel }}</button></section>`,
};
const context = () => ({
  capabilities: { configure: true, configuration_global: true },
  units: [],
  pause_catalog: { role_options: [] },
});
const render = (props = {}) =>
  mount(PauseCatalogEditor, {
    props: { accountId: '1', context: context(), ...props },
    global: {
      stubs: {
        RouterLink: true,
        Dialog,
        Button: {
          props: ['label', 'disabled'],
          template: '<button :disabled="disabled">{{ label }}</button>',
        },
      },
    },
  });
const button = (wrapper, key) =>
  wrapper.findAll('button').find(node => node.text() === copy(key));
const field = (wrapper, name) =>
  wrapper
    .findAll('label')
    .find(node => node.text().startsWith(copy(name)))
    .find('input');
enableAutoUnmount(afterEach);
beforeEach(() => {
  vi.clearAllMocks();
  mocks.route = reactive({ query: {} });
  mocks.replace.mockImplementation(async ({ query }) => {
    mocks.route.query = Object.fromEntries(
      Object.entries(query).filter(([, value]) => value !== undefined)
    );
  });
  API.pauseCatalog.mockResolvedValue({ data: { item: snapshot() } });
  API.updatePauseCatalog.mockResolvedValue({ data: { item: snapshot() } });
});

describe('native pause catalog editor', () => {
  it('loads the account-bound catalog without activating or writing any configuration', async () => {
    const wrapper = render();
    await flushPromises();
    expect(API.pauseCatalog).toHaveBeenCalledWith('1');
    expect(wrapper.text()).toContain(copy('LEGACY'));
    expect(wrapper.text()).toContain(definition.name);
    expect(API.updatePauseCatalog).not.toHaveBeenCalled();
  });

  it('opens real minute values as HH:MM and cancels without changing the catalog', async () => {
    const wrapper = render();
    await flushPromises();
    await button(wrapper, 'EDIT').trigger('click');
    expect(field(wrapper, 'MINIMUM_MINUTES').element.value).toBe('00:15');
    expect(field(wrapper, 'DEFAULT_MINUTES').element.value).toBe('00:30');
    expect(field(wrapper, 'MAXIMUM_MINUTES').element.value).toBe('01:00');
    await field(wrapper, 'NAME').setValue('SYNTHETIC unsaved');
    await wrapper.get('[data-cancel]').trigger('click');
    expect(API.updatePauseCatalog).not.toHaveBeenCalled();
    expect(wrapper.text()).toContain(definition.name);
  });

  it('saves literal integer minutes and preserves disabled enforcement unless the policy dialog explicitly changes it', async () => {
    const wrapper = render();
    await flushPromises();
    await button(wrapper, 'EDIT').trigger('click');
    await field(wrapper, 'DEFAULT_MINUTES').setValue('00:45');
    await wrapper.get('[data-confirm]').trigger('click');
    await flushPromises();
    expect(API.updatePauseCatalog).toHaveBeenCalledWith(
      '1',
      expect.objectContaining({
        enforced: false,
        entries: [
          expect.objectContaining({
            minimum_minutes: 15,
            default_minutes: 45,
            maximum_minutes: 60,
          }),
        ],
      }),
      { expected_revision: 'a'.repeat(64), activation_confirmed: false }
    );
    expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
    expect(wrapper.emitted('changed')).toHaveLength(1);
    await button(wrapper, 'EDIT').trigger('click');
    expect(wrapper.find('[role="dialog"]').exists()).toBe(true);
  });

  it('blocks inconsistent maximum and keeps the edited fields visible instead of clamping them', async () => {
    const wrapper = render();
    await flushPromises();
    await button(wrapper, 'EDIT').trigger('click');
    await field(wrapper, 'MAXIMUM_MINUTES').setValue('00:10');
    expect(wrapper.get('[data-confirm]').attributes('disabled')).toBeDefined();
    expect(field(wrapper, 'MAXIMUM_MINUTES').attributes('aria-invalid')).toBe(
      'true'
    );
    expect(field(wrapper, 'MAXIMUM_MINUTES').element.value).toBe('00:10');
    expect(API.updatePauseCatalog).not.toHaveBeenCalled();
  });

  it('preserves a rejected server draft and does not close the popup or report it saved', async () => {
    API.updatePauseCatalog.mockRejectedValueOnce({
      response: {
        status: 422,
        data: { invalid_attributes: ['name', 'description'] },
      },
    });
    const wrapper = render();
    await flushPromises();
    await button(wrapper, 'EDIT').trigger('click');
    const invalidFocus = vi.spyOn(field(wrapper, 'NAME').element, 'focus');
    await field(wrapper, 'NAME').setValue('SYNTHETIC retained draft');
    await wrapper.get('textarea').setValue('SYNTHETIC retained description');
    await wrapper.get('[data-confirm]').trigger('click');
    await flushPromises();
    expect(field(wrapper, 'NAME').element.value).toBe(
      'SYNTHETIC retained draft'
    );
    expect(wrapper.text()).toContain(copy('SAVE_FAILED'));
    expect(wrapper.emitted('changed')).toBeUndefined();
    expect(wrapper.get('[role="dialog"]').exists()).toBe(true);
    expect(field(wrapper, 'NAME').attributes('aria-invalid')).toBe('true');
    expect(invalidFocus).toHaveBeenCalledWith({ preventScroll: true });
    expect(wrapper.get('textarea').element.value).toBe(
      'SYNTHETIC retained description'
    );
    expect(wrapper.get('textarea').attributes('aria-invalid')).toBe('true');
    expect(wrapper.findAll('[data-pause-invalid-field]')).toHaveLength(2);
    expect(wrapper.get('[data-pause-invalid-field="name"]').text()).toBe(
      copy('INVALID_FIELD')
    );
    expect(wrapper.get('[data-pause-invalid-field="description"]').text()).toBe(
      copy('INVALID_FIELD')
    );
    await wrapper.get('[data-confirm]').trigger('click');
    await flushPromises();
    expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
    expect(wrapper.emitted('changed')).toHaveLength(1);
  });

  it('requires the explicit checkbox before submitting account-wide enforcement', async () => {
    const wrapper = render();
    await flushPromises();
    await button(wrapper, 'ENABLE').trigger('click');
    expect(wrapper.get('[data-confirm]').attributes('disabled')).toBeDefined();
    await wrapper.get('[role="dialog"] input[type="checkbox"]').setValue(true);
    await wrapper.get('[data-confirm]').trigger('click');
    await flushPromises();
    expect(API.updatePauseCatalog).toHaveBeenCalledWith(
      '1',
      { enforced: true, entries: [definition] },
      { expected_revision: 'a'.repeat(64), activation_confirmed: true }
    );
  });

  it('does not offer or load global configuration to a unit-restricted configurator', async () => {
    const scoped = context();
    scoped.capabilities.configuration_global = false;
    const wrapper = render({ context: scoped });
    await flushPromises();
    expect(API.pauseCatalog).not.toHaveBeenCalled();
    expect(wrapper.text()).toContain(copy('GLOBAL_DENIED'));
    expect(wrapper.text()).not.toContain(definition.name);
    expect(wrapper.findAll('button')).toHaveLength(0);
  });

  it('does not substitute a global scope indicator for actual configure permission', async () => {
    const denied = context();
    denied.capabilities.configure = false;
    const wrapper = render({ context: denied });
    await flushPromises();
    expect(API.pauseCatalog).not.toHaveBeenCalled();
    expect(wrapper.text()).not.toContain(definition.name);
  });

  it('ignores a delayed old account response and clears a popup when access is withdrawn', async () => {
    let finish;
    API.pauseCatalog.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const wrapper = render();
    API.pauseCatalog.mockResolvedValue({
      data: {
        item: snapshot(
          [{ ...definition, name: 'SYNTHETIC current account' }],
          '2'
        ),
      },
    });
    await wrapper.setProps({ accountId: '2' });
    await flushPromises();
    finish({
      data: {
        item: snapshot([
          { ...definition, name: 'SYNTHETIC stale private account' },
        ]),
      },
    });
    await flushPromises();
    expect(wrapper.text()).not.toContain('SYNTHETIC stale private account');
    expect(wrapper.text()).toContain('SYNTHETIC current account');
    await button(wrapper, 'EDIT').trigger('click');
    const revoked = context();
    revoked.capabilities.configuration_global = false;
    await wrapper.setProps({ context: revoked });
    await flushPromises();
    expect(wrapper.text()).not.toContain('SYNTHETIC current account');
    expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
  });

  it('rejects a mismatched Account identity instead of rendering its contents', async () => {
    API.pauseCatalog.mockResolvedValueOnce({
      data: {
        item: snapshot(
          [{ ...definition, name: 'SYNTHETIC wrong account' }],
          '99'
        ),
      },
    });
    const wrapper = render();
    await flushPromises();
    expect(wrapper.text()).not.toContain('SYNTHETIC wrong account');
    expect(wrapper.text()).toContain(copy('LOAD_FAILED'));
    expect(button(wrapper, 'CREATE')).toBeUndefined();
  });

  it('requires fresh comparison after a conflict and invalidates that review after a draft edit', async () => {
    API.updatePauseCatalog.mockRejectedValueOnce({
      response: {
        status: 409,
        data: { error: 'stale_configuration_revision' },
      },
    });
    const wrapper = render();
    await flushPromises();
    await button(wrapper, 'EDIT').trigger('click');
    await field(wrapper, 'NAME').setValue('SYNTHETIC retained conflict');
    await wrapper.get('[data-confirm]').trigger('click');
    await flushPromises();
    expect(wrapper.get('[data-confirm]').attributes('disabled')).toBeDefined();
    API.pauseCatalog.mockResolvedValueOnce({
      data: {
        item: snapshot(
          [{ ...definition, name: 'SYNTHETIC concurrent' }],
          '1',
          'b'.repeat(64)
        ),
      },
    });
    const reload = wrapper
      .findAll('button')
      .find(
        node =>
          node.text() === 'JRC_CONTACT_CENTER.CONFIGURATION_REVISION.RELOAD'
      );
    await reload.trigger('click');
    await flushPromises();
    expect(field(wrapper, 'NAME').element.value).toBe(
      'SYNTHETIC retained conflict'
    );
    expect(wrapper.get('[data-configuration-latest]').text()).toContain(
      'SYNTHETIC concurrent'
    );
    await wrapper.get('[data-configuration-review]').setValue(true);
    expect(
      wrapper.get('[data-confirm]').attributes('disabled')
    ).toBeUndefined();
    await field(wrapper, 'NAME').setValue('SYNTHETIC revised again');
    expect(wrapper.get('[data-confirm]').attributes('disabled')).toBeDefined();
    await wrapper.get('[data-configuration-review]').setValue(true);
    await wrapper.get('[data-confirm]').trigger('click');
    await flushPromises();
    expect(API.updatePauseCatalog).toHaveBeenLastCalledWith(
      '1',
      expect.objectContaining({
        entries: [expect.objectContaining({ name: 'SYNTHETIC revised again' })],
      }),
      { expected_revision: 'b'.repeat(64), activation_confirmed: false }
    );
  });

  it('paginates twenty real reasons and resets the URL page when filtering or clearing the search', async () => {
    const entries = Array.from({ length: 21 }, (_, index) => ({
      ...definition,
      code: `synthetic_${index}`,
      name: `SYNTHETIC row ${String(index).padStart(2, '0')}`,
    }));
    API.pauseCatalog.mockResolvedValueOnce({
      data: { item: snapshot(entries) },
    });
    const wrapper = render();
    await flushPromises();
    expect(wrapper.findAll('article')).toHaveLength(20);
    await button(wrapper, 'NEXT').trigger('click');
    await flushPromises();
    expect(mocks.route.query.pauses_page).toBe('2');
    expect(wrapper.findAll('article')).toHaveLength(1);
    expect(wrapper.find('article').text()).toContain('SYNTHETIC row 20');
    await wrapper.get('input[type="search"]').setValue('row 00');
    await flushPromises();
    expect(mocks.route.query.pauses_page).toBeUndefined();
    expect(wrapper.findAll('article')).toHaveLength(1);
    await wrapper.get('input[type="search"]').setValue('');
    await flushPromises();
    expect(wrapper.findAll('article')).toHaveLength(20);
    expect(mocks.route.query.pauses_q).toBeUndefined();
  });

  it('saves an optional literal justification policy without enabling catalog enforcement', async () => {
    const wrapper = render();
    await flushPromises();
    await button(wrapper, 'EDIT').trigger('click');
    expect(field(wrapper, 'JUSTIFICATION_REQUIRED').element.checked).toBe(
      false
    );
    await field(wrapper, 'JUSTIFICATION_REQUIRED').setValue(true);
    await wrapper.get('[data-confirm]').trigger('click');
    await flushPromises();
    expect(API.updatePauseCatalog).toHaveBeenLastCalledWith(
      '1',
      expect.objectContaining({
        enforced: false,
        entries: [expect.objectContaining({ justification_required: true })],
      }),
      { expected_revision: 'a'.repeat(64), activation_confirmed: false }
    );
  });

  it('does not add the new policy to an unchanged old-format entry merely by opening and saving it', async () => {
    const wrapper = render();
    await flushPromises();
    await button(wrapper, 'EDIT').trigger('click');
    expect(field(wrapper, 'JUSTIFICATION_REQUIRED').element.checked).toBe(
      false
    );
    await wrapper.get('[data-confirm]').trigger('click');
    await flushPromises();
    expect(
      API.updatePauseCatalog.mock.calls.at(-1)[1].entries[0]
    ).not.toHaveProperty('justification_required');
  });
});

it('keeps the legacy alert checked but does not inject a flag into an ordinary edit', async () => {
  const wrapper = render();
  await flushPromises();
  await button(wrapper, 'EDIT').trigger('click');
  expect(wrapper.get('[data-pause-time-alert]').element.checked).toBe(true);
  await field(wrapper, 'NAME').setValue('SYNTHETIC reviewed legacy name');
  await wrapper.get('[data-confirm]').trigger('click');
  await flushPromises();
  const saved = API.updatePauseCatalog.mock.calls[0][1].entries[0];
  expect(saved).not.toHaveProperty('time_alert_enabled');
  expect(saved.maximum_minutes).toBe(60);
  expect(definition).not.toHaveProperty('time_alert_enabled');
});
it('persists an explicitly disabled alert without changing limits, scopes or enforcement', async () => {
  const wrapper = render();
  await flushPromises();
  await button(wrapper, 'EDIT').trigger('click');
  await wrapper.get('[data-pause-time-alert]').setValue(false);
  await wrapper.get('[data-confirm]').trigger('click');
  await flushPromises();
  expect(API.updatePauseCatalog.mock.calls[0][1]).toEqual({
    enforced: false,
    entries: [{ ...definition, time_alert_enabled: false }],
  });
  expect(API.updatePauseCatalog).toHaveBeenCalledTimes(1);
});
it('retains the selected alert policy after an upload-free API failure and retries only on an explicit save', async () => {
  API.updatePauseCatalog.mockRejectedValueOnce({ response: { status: 500 } });
  const wrapper = render();
  await flushPromises();
  await button(wrapper, 'EDIT').trigger('click');
  await wrapper.get('[data-pause-time-alert]').setValue(false);
  await field(wrapper, 'NAME').setValue('SYNTHETIC retained alert draft');
  await wrapper.get('[data-confirm]').trigger('click');
  await flushPromises();
  expect(wrapper.get('[role="dialog"]').exists()).toBe(true);
  expect(wrapper.get('[data-pause-time-alert]').element.checked).toBe(false);
  expect(field(wrapper, 'NAME').element.value).toBe(
    'SYNTHETIC retained alert draft'
  );
  expect(API.updatePauseCatalog).toHaveBeenCalledTimes(1);
  await wrapper.get('[data-pause-time-alert]').setValue(true);
  await wrapper.get('[data-confirm]').trigger('click');
  await flushPromises();
  expect(API.updatePauseCatalog).toHaveBeenCalledTimes(2);
  expect(
    API.updatePauseCatalog.mock.calls[1][1].entries[0].time_alert_enabled
  ).toBe(true);
});
