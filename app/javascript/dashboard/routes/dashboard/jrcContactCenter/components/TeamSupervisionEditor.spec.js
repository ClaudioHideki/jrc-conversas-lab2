import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { computed, defineComponent, ref } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import TeamSupervisionEditor from './TeamSupervisionEditor.vue';

vi.mock('dashboard/components-next/dialog/Dialog.vue', () => ({
  default: { name: 'Dialog', render: () => null },
}));
vi.mock('dashboard/components-next/button/Button.vue', () => ({
  default: { name: 'Button', render: () => null },
}));
const state = vi.hoisted(() => ({ user: null }));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => state.user,
}));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, values) => `${key}${values?.name ? ` ${values.name}` : ''}`,
  }),
}));
vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: {
    configurationRecord: vi.fn(),
    teamSupervisionCandidates: vi.fn(),
    saveTeamSupervision: vi.fn(),
  },
}));
const Dialog = defineComponent({
  props: { disableConfirmButton: Boolean },
  emits: ['confirm', 'close'],
  setup(props, { expose, emit }) {
    const visible = ref(false);
    expose({
      open: () => {
        visible.value = true;
      },
      close: () => {
        visible.value = false;
      },
    });
    return {
      saveLabel: 'SAVE',
      closeLabel: 'CLOSE',
      visible,
      disabled: computed(() => props.disableConfirmButton),
      confirm: () => emit('confirm'),
      dismiss: () => {
        visible.value = false;
        emit('close');
      },
    };
  },
  template:
    '<form v-if="visible" role="dialog" @submit.prevent="confirm"><slot /><button data-save :disabled="disabled">{{ saveLabel }}</button><button type="button" data-close @click="dismiss">{{ closeLabel }}</button></form>',
});
const person = (id, eligible = true) => ({
  account_user_id: id,
  name: `SYNTHETIC supervisor ${id}`,
  eligible,
  reason: eligible ? null : 'coverage',
});
const record = (overrides = {}) => ({
  id: '4',
  name: 'SYNTHETIC team',
  active: true,
  revision: 'a'.repeat(64),
  primary_account_user_id: null,
  additional_account_user_ids: [],
  supervisors: [],
  ...overrides,
});
const fixture = () =>
  mount(TeamSupervisionEditor, {
    props: { accountId: '1', teamId: '4', teamName: 'SYNTHETIC team' },
    global: { stubs: { Dialog } },
  });
const open = async wrapper => {
  await wrapper.get('[data-team-supervision-open="4"]').trigger('click');
  await flushPromises();
};
enableAutoUnmount(afterEach);
beforeEach(() => {
  vi.resetAllMocks();
  state.user = ref({
    id: 7,
    accounts: [{ id: 1, role: 'administrator', permissions: [] }],
  });
  API.configurationRecord.mockResolvedValue({
    data: { account_id: '1', item: record() },
  });
  API.teamSupervisionCandidates.mockResolvedValue({
    data: {
      account_id: '1',
      items: [person('7'), person('8'), person('9', false)],
      meta: { page: 1, pages: 2, total: 21 },
    },
  });
  API.saveTeamSupervision.mockResolvedValue({
    data: { account_id: '1', item: record() },
  });
});

describe('team supervision native popup (transport fixtures)', () => {
  it('opens deliberately with real candidate names and no invented primary or automatic request', async () => {
    const wrapper = fixture();
    expect(API.configurationRecord).not.toHaveBeenCalled();
    await open(wrapper);
    expect(wrapper.get('[role="dialog"]').text()).toContain(
      'SYNTHETIC supervisor 7'
    );
    expect(wrapper.find('[data-team-supervision-primary]').exists()).toBe(
      false
    );
    expect(wrapper.get('[data-save]').element.disabled).toBe(true);
    expect(
      wrapper.get('[data-team-supervision-choose-primary="9"]').element.disabled
    ).toBe(true);
    expect(API.saveTeamSupervision).not.toHaveBeenCalled();
  });

  it('requires reviewed primary/additional selection and closes only after the actual save resolves', async () => {
    const wrapper = fixture();
    await open(wrapper);
    await wrapper
      .get('[data-team-supervision-choose-primary="7"]')
      .trigger('click');
    await wrapper.get('[data-team-supervision-additional="8"]').setValue(true);
    expect(wrapper.get('[data-save]').element.disabled).toBe(true);
    await wrapper.get('[data-team-supervision-review]').setValue(true);
    await wrapper.get('[role="dialog"]').trigger('submit');
    await flushPromises();
    expect(API.saveTeamSupervision).toHaveBeenCalledWith(
      '1',
      '4',
      { primary_account_user_id: '7', additional_account_user_ids: ['8'] },
      { expected_revision: 'a'.repeat(64) }
    );
    expect(wrapper.emitted('changed')).toHaveLength(1);
    expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
  });

  it('invalidates review after removal and keeps primary/additional controls separate', async () => {
    const wrapper = fixture();
    await open(wrapper);
    await wrapper
      .get('[data-team-supervision-choose-primary="7"]')
      .trigger('click');
    await wrapper.get('[data-team-supervision-additional="8"]').setValue(true);
    await wrapper.get('[data-team-supervision-review]').setValue(true);
    await wrapper
      .get('[data-team-supervision-remove-additional="8"]')
      .trigger('click');
    expect(wrapper.get('[data-save]').element.disabled).toBe(true);
    expect(wrapper.get('[data-team-supervision-review]').element.checked).toBe(
      false
    );
    await wrapper
      .get('[data-team-supervision-remove-primary]')
      .trigger('click');
    expect(wrapper.find('[data-team-supervision-primary]').exists()).toBe(
      false
    );
    expect(API.saveTeamSupervision).not.toHaveBeenCalled();
  });

  it('searches and paginates without submitting the containing editor or dropping selected names', async () => {
    const wrapper = fixture();
    await open(wrapper);
    await wrapper
      .get('[data-team-supervision-choose-primary="7"]')
      .trigger('click');
    await wrapper
      .get('input[id^="team-supervision-search-"]')
      .setValue('SYNTHETIC search');
    await wrapper
      .get('input[id^="team-supervision-search-"]')
      .trigger('keydown', { key: 'Enter' });
    await flushPromises();
    expect(API.teamSupervisionCandidates).toHaveBeenLastCalledWith('1', '4', {
      page: 1,
      per_page: 20,
      q: 'SYNTHETIC search',
    });
    await wrapper.get('[data-team-supervision-next]').trigger('click');
    await flushPromises();
    expect(API.teamSupervisionCandidates).toHaveBeenLastCalledWith('1', '4', {
      page: 2,
      per_page: 20,
      q: 'SYNTHETIC search',
    });
    expect(wrapper.get('[data-team-supervision-primary]').text()).toBe(
      'SYNTHETIC supervisor 7'
    );
    expect(wrapper.findAll('form')).toHaveLength(1);
    expect(API.saveTeamSupervision).not.toHaveBeenCalled();
  });

  it('clears private names and closes after the authenticated profile changes', async () => {
    const wrapper = fixture();
    await open(wrapper);
    state.user.value = {
      ...state.user.value,
      accounts: [
        { id: 1, role: 'agent', permissions: ['jrc_contact_center_view'] },
      ],
    };
    await flushPromises();
    expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
    expect(wrapper.text()).not.toContain('SYNTHETIC supervisor');
    expect(API.saveTeamSupervision).not.toHaveBeenCalled();
  });

  it('clears data and emits denial rather than retaining a dialog after a server rejection', async () => {
    const wrapper = fixture();
    API.configurationRecord.mockRejectedValueOnce({
      response: { status: 403 },
    });
    await open(wrapper);
    expect(wrapper.emitted('denied')).toHaveLength(1);
    expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
    expect(wrapper.text()).not.toContain('SYNTHETIC supervisor');
  });

  it('preserves an editable rejected draft and requires a fresh review before retry', async () => {
    const wrapper = fixture();
    API.saveTeamSupervision.mockRejectedValueOnce({
      response: { status: 422, data: { error: 'ineligible_team_supervisor' } },
    });
    await open(wrapper);
    await wrapper
      .get('[data-team-supervision-choose-primary="7"]')
      .trigger('click');
    await wrapper.get('[data-team-supervision-review]').setValue(true);
    await wrapper.get('[role="dialog"]').trigger('submit');
    await flushPromises();
    expect(wrapper.get('[data-team-supervision-primary]').text()).toBe(
      'SYNTHETIC supervisor 7'
    );
    expect(wrapper.get('[role="alert"]').text()).toContain('INELIGIBLE');
    expect(wrapper.get('[data-save]').element.disabled).toBe(true);
    expect(wrapper.emitted('changed')).toBeUndefined();
  });
});
