import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { computed, defineComponent, reactive, ref } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import AuthorityAssignments from './AuthorityAssignments.vue';

const mocks = vi.hoisted(() => ({ route: null, replace: vi.fn() }));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () =>
    ref({ id: 7, accounts: [{ id: 1, role: 'administrator' }] }),
}));
vi.mock('vue-router', () => ({
  useRoute: () => mocks.route,
  useRouter: () => ({ replace: mocks.replace }),
}));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, values) => (values?.teams ? `${key} ${values.teams}` : key),
  }),
}));
vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: {
    accessAuthorizations: vi.fn(),
    configurationRecord: vi.fn(),
    saveAccessAuthorization: vi.fn(),
  },
}));
const Dialog = defineComponent({
  props: { disableConfirmButton: Boolean },
  emits: ['confirm'],
  setup(props, { expose, emit }) {
    const visible = ref(false);
    const disabled = computed(() => props.disableConfirmButton);
    expose({
      open: () => {
        visible.value = true;
      },
      close: () => {
        visible.value = false;
      },
    });
    return { visible, disabled, confirm: () => emit('confirm') };
  },
  template:
    '<form v-if="visible" role="dialog" @submit.prevent="confirm"><slot /><button data-submit type="submit" :disabled="disabled">SAVE</button></form>',
});
enableAutoUnmount(afterEach);
const source = overrides => ({
  id: 9,
  name: 'SYNTHETIC native member',
  revision: 'a'.repeat(64),
  eligible: false,
  allowed: [],
  denied: [],
  profile: ['jrc_contact_center_view'],
  inherited: [],
  effective: [],
  ...overrides,
});
const setup = (type = 'users') =>
  mount(AuthorityAssignments, {
    props: { accountId: '1', subjectType: type },
    global: { stubs: { Dialog } },
  });
beforeEach(() => {
  vi.clearAllMocks();
  mocks.route = reactive({ query: {} });
  API.accessAuthorizations.mockResolvedValue({
    data: { items: [source()], meta: { page: 1, pages: 2, total: 21 } },
  });
  API.configurationRecord.mockResolvedValue({ data: { item: source() } });
  API.saveAccessAuthorization.mockResolvedValue({ data: { item: source() } });
});

describe('native subject authorizations', () => {
  it.each(['users', 'teams'])(
    'shows the independent review right unchecked for %s without automatic persistence',
    async type => {
      const wrapper = setup(type);
      await flushPromises();
      await wrapper.get('[data-edit-authority="9"]').trigger('click');
      await flushPromises();
      expect(
        wrapper.get('[data-allow="jrc_contact_center_quality_review"]').element
          .checked
      ).toBe(false);
      expect(wrapper.text()).toContain(
        'CUSTOM_ROLE.PERMISSIONS.JRC_CONTACT_CENTER_QUALITY_REVIEW'
      );
      expect(wrapper.get('[data-submit]').element.disabled).toBe(true);
      expect(API.saveAccessAuthorization).not.toHaveBeenCalled();
    }
  );

  it('requires explicit review before saving the independent quality-review denial', async () => {
    const wrapper = setup();
    await flushPromises();
    await wrapper.get('[data-edit-authority="9"]').trigger('click');
    await flushPromises();
    await wrapper
      .get('[data-deny="jrc_contact_center_quality_review"]')
      .setValue(true);
    expect(wrapper.get('[data-submit]').element.disabled).toBe(true);
    expect(API.saveAccessAuthorization).not.toHaveBeenCalled();
    await wrapper.get('[data-review-authority]').setValue(true);
    await wrapper.get('[data-submit]').trigger('submit');
    await flushPromises();
    expect(API.saveAccessAuthorization.mock.calls[0][3]).toEqual({
      eligible: false,
      allowed: [],
      denied: ['jrc_contact_center_quality_review'],
    });
  });

  it('identifies the authorized profile and exact team origin without treating inheritance as eligibility', async () => {
    API.configurationRecord.mockResolvedValue({
      data: {
        item: source({
          inherited: ['jrc_contact_center_monitor'],
          origins: {
            profile: { id: 3, name: 'Reviewed native profile' },
            teams: [
              {
                id: 4,
                name: 'SYNTHETIC team <escaped>',
                permissions: ['jrc_contact_center_monitor'],
              },
              {
                id: 5,
                name: 'Other actual team',
                permissions: ['jrc_contact_center_publish'],
              },
            ],
          },
        }),
      },
    });
    const wrapper = setup();
    await flushPromises();
    await wrapper.get('[data-edit-authority="9"]').trigger('click');
    await flushPromises();
    expect(wrapper.get('[data-profile-origin]').text()).toContain(
      'Reviewed native profile'
    );
    const origin = wrapper.get(
      '[data-inherited-origin="jrc_contact_center_monitor"]'
    );
    expect(origin.text()).toContain('SYNTHETIC team <escaped>');
    expect(origin.text()).not.toContain('Other actual team');
    expect(origin.find('escaped').exists()).toBe(false);
    expect(wrapper.get('[data-user-eligible]').element.checked).toBe(false);
    expect(wrapper.get('[data-submit]').element.disabled).toBe(true);
    expect(API.saveAccessAuthorization).not.toHaveBeenCalled();
  });

  it('loads only the chosen account and reads a fresh revision before opening', async () => {
    const wrapper = setup();
    await flushPromises();
    expect(API.accessAuthorizations).toHaveBeenCalledWith('1', 'users', {
      page: 1,
      per_page: 20,
      q: '',
      status: '',
    });
    await wrapper.get('[data-edit-authority="9"]').trigger('click');
    await flushPromises();
    expect(API.configurationRecord).toHaveBeenCalledWith(
      '1',
      'access_users',
      9
    );
    expect(wrapper.get('[data-user-eligible]').element.checked).toBe(false);
    expect(wrapper.get('[data-submit]').element.disabled).toBe(true);
  });

  it('requires review and sends the explicit eligibility with the captured revision', async () => {
    const wrapper = setup();
    await flushPromises();
    await wrapper.get('[data-edit-authority="9"]').trigger('click');
    await flushPromises();
    await wrapper.get('[data-user-eligible]').setValue(true);
    expect(wrapper.get('[data-submit]').element.disabled).toBe(true);
    await wrapper.get('[data-review-authority]').setValue(true);
    await wrapper.get('[data-submit]').trigger('submit');
    await flushPromises();
    expect(API.saveAccessAuthorization).toHaveBeenCalledWith(
      '1',
      'users',
      9,
      { eligible: true, allowed: [], denied: [] },
      { expected_revision: 'a'.repeat(64) }
    );
    expect(wrapper.emitted('changed')).toHaveLength(1);
  });

  it('invalidates the review when the draft changes and retains independent denials', async () => {
    const wrapper = setup();
    await flushPromises();
    await wrapper.get('[data-edit-authority="9"]').trigger('click');
    await flushPromises();
    await wrapper.get('[data-review-authority]').setValue(true);
    await wrapper
      .get('[data-deny="jrc_contact_center_publish"]')
      .setValue(true);
    expect(wrapper.get('[data-review-authority]').element.checked).toBe(false);
    expect(wrapper.get('[data-submit]').element.disabled).toBe(true);
    await wrapper.get('[data-review-authority]').setValue(true);
    await wrapper.get('[data-submit]').trigger('submit');
    await flushPromises();
    expect(API.saveAccessAuthorization.mock.calls[0][3].denied).toEqual([
      'jrc_contact_center_publish',
    ]);
  });

  it('never submits user eligibility or denial fields for a team', async () => {
    const wrapper = setup('teams');
    await flushPromises();
    await wrapper.get('[data-edit-authority="9"]').trigger('click');
    await flushPromises();
    expect(wrapper.get('[role="dialog"]').text()).toContain(
      'JRC_CONTACT_CENTER.ACCESS.TEAM_ALLOWED'
    );
    expect(wrapper.get('[role="dialog"]').text()).not.toContain(
      'JRC_CONTACT_CENTER.ACCESS.ALLOWED'
    );
    expect(wrapper.find('[data-user-eligible]').exists()).toBe(false);
    expect(wrapper.find('[data-deny]').exists()).toBe(false);
    await wrapper
      .get('[data-allow="jrc_contact_center_monitor"]')
      .setValue(true);
    await wrapper.get('[data-review-authority]').setValue(true);
    await wrapper.get('[data-submit]').trigger('submit');
    await flushPromises();
    expect(API.saveAccessAuthorization.mock.calls[0].slice(0, 4)).toEqual([
      '1',
      'teams',
      9,
      { allowed: ['jrc_contact_center_monitor'], active: true },
    ]);
  });

  it('keeps a rejected draft and requires current-state comparison after a conflict', async () => {
    API.saveAccessAuthorization.mockRejectedValueOnce({
      response: { data: { error: 'stale_configuration_revision' } },
    });
    const wrapper = setup();
    await flushPromises();
    await wrapper.get('[data-edit-authority="9"]').trigger('click');
    await flushPromises();
    await wrapper.get('[data-user-eligible]').setValue(true);
    await wrapper.get('[data-review-authority]').setValue(true);
    await wrapper.get('[data-submit]').trigger('submit');
    await flushPromises();
    expect(wrapper.get('[data-user-eligible]').element.checked).toBe(true);
    expect(wrapper.find('[data-configuration-conflict]').exists()).toBe(true);
    expect(wrapper.get('[data-submit]').element.disabled).toBe(true);
  });

  it('does not enable a write when the server omitted the revision', async () => {
    API.configurationRecord.mockResolvedValueOnce({
      data: { item: source({ revision: undefined }) },
    });
    const wrapper = setup();
    await flushPromises();
    await wrapper.get('[data-edit-authority="9"]').trigger('click');
    await flushPromises();
    await wrapper.get('[data-review-authority]').setValue(true);
    await wrapper.get('[role="dialog"]').trigger('submit');
    await flushPromises();
    expect(API.saveAccessAuthorization).not.toHaveBeenCalled();
  });

  it('preserves content and makes failures visible without an automatic retry', async () => {
    API.saveAccessAuthorization.mockRejectedValueOnce(
      new Error('Synthetic unavailable')
    );
    const wrapper = setup();
    await flushPromises();
    await wrapper.get('[data-edit-authority="9"]').trigger('click');
    await flushPromises();
    await wrapper.get('[data-user-eligible]').setValue(true);
    await wrapper.get('[data-review-authority]').setValue(true);
    await wrapper.get('[data-submit]').trigger('submit');
    await flushPromises();
    expect(wrapper.get('[data-user-eligible]').element.checked).toBe(true);
    expect(wrapper.find('[role="alert"]').exists()).toBe(true);
    expect(API.saveAccessAuthorization).toHaveBeenCalledTimes(1);
  });

  it('prevents two pending writes from repeated submissions', async () => {
    let resolve;
    API.saveAccessAuthorization.mockReturnValueOnce(
      new Promise(done => {
        resolve = done;
      })
    );
    const wrapper = setup();
    await flushPromises();
    await wrapper.get('[data-edit-authority="9"]').trigger('click');
    await flushPromises();
    await wrapper.get('[data-review-authority]').setValue(true);
    await wrapper.get('[role="dialog"]').trigger('submit');
    await wrapper.get('[role="dialog"]').trigger('submit');
    expect(API.saveAccessAuthorization).toHaveBeenCalledTimes(1);
    resolve({ data: {} });
    await flushPromises();
  });

  it('discards the prior account detail response during account switching', async () => {
    let resolve;
    API.configurationRecord.mockReturnValueOnce(
      new Promise(done => {
        resolve = done;
      })
    );
    const wrapper = setup();
    await flushPromises();
    await wrapper.get('[data-edit-authority="9"]').trigger('click');
    await wrapper.setProps({ accountId: '2' });
    await flushPromises();
    resolve({ data: { item: source() } });
    await flushPromises();
    expect(wrapper.find('[data-authority-editor]').exists()).toBe(false);
    expect(API.accessAuthorizations.mock.calls.at(-1)[0]).toBe('2');
  });

  it('writes search, eligibility and pagination to the native route query', async () => {
    const wrapper = setup();
    await flushPromises();
    await wrapper.find('input').setValue('SYNTHETIC');
    await wrapper.find('select').setValue('pending');
    await wrapper.find('form').trigger('submit');
    expect(mocks.replace).toHaveBeenCalledWith({
      query: {
        access_users_q: 'SYNTHETIC',
        access_users_status: 'pending',
        access_users_page: 1,
      },
    });
  });

  it('can reopen after a successful save instead of remaining busy', async () => {
    const wrapper = setup();
    await flushPromises();
    await wrapper.get('[data-edit-authority="9"]').trigger('click');
    await flushPromises();
    await wrapper.get('[data-review-authority]').setValue(true);
    await wrapper.get('[data-submit]').trigger('submit');
    await flushPromises();
    await wrapper.get('[data-edit-authority="9"]').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-authority-editor]').exists()).toBe(true);
  });
  it('sends only module-local inactive state while preserving all configured team capabilities', async () => {
    API.configurationRecord.mockResolvedValue({
      data: {
        item: source({ active: true, allowed: ['jrc_contact_center_monitor'] }),
      },
    });
    const wrapper = setup('teams');
    await flushPromises();
    await wrapper.get('[data-edit-authority="9"]').trigger('click');
    await flushPromises();
    await wrapper.get('[data-team-source-active]').setValue(false);
    await wrapper.get('[data-review-authority]').setValue(true);
    await wrapper.get('[data-submit]').trigger('submit');
    await flushPromises();
    expect(API.saveAccessAuthorization.mock.calls[0][3]).toEqual({
      active: false,
      allowed: ['jrc_contact_center_monitor'],
    });
    expect(wrapper.find('[data-user-eligible]').exists()).toBe(false);
  });

  it('requires the manager receipt before retrying a source withdrawal and clears it if the draft changes', async () => {
    API.saveAccessAuthorization.mockRejectedValueOnce({
      response: {
        data: {
          error: 'team_roster_confirmation_required',
          review: {
            account_id: '1',
            team_id: '9',
            team_name: 'SYNTHETIC team',
            operation: 'deactivate_source',
            queues: [
              {
                queue_id: '4',
                unit_id: '5',
                queue_name: 'SYNTHETIC last queue',
                previous_count: 1,
                remaining_count: 0,
              },
            ],
            review_token: 'synthetic-signed-server-receipt',
          },
        },
      },
    });
    const wrapper = setup('teams');
    await flushPromises();
    await wrapper.get('[data-edit-authority="9"]').trigger('click');
    await flushPromises();
    await wrapper.get('[data-team-source-active]').setValue(false);
    await wrapper.get('[data-review-authority]').setValue(true);
    await wrapper.get('[data-submit]').trigger('submit');
    await flushPromises();
    expect(wrapper.get('[data-submit]').element.disabled).toBe(true);
    await wrapper.get('[data-team-manager-withdrawal-confirm]').setValue(true);
    await wrapper.get('[data-review-authority]').setValue(true);
    expect(wrapper.get('[data-submit]').element.disabled).toBe(false);
    await wrapper.get('[data-team-source-active]').setValue(true);
    expect(
      wrapper.find('[data-team-manager-withdrawal-confirm]').exists()
    ).toBe(false);
    expect(wrapper.get('[data-submit]').element.disabled).toBe(true);
    expect(API.saveAccessAuthorization).toHaveBeenCalledTimes(1);
  });

  it('names suspended origins without presenting them as effective inherited capabilities', async () => {
    API.configurationRecord.mockResolvedValue({
      data: {
        item: source({
          origins: {
            teams: [
              {
                id: 3,
                name: 'SYNTHETIC inactive team',
                active: false,
                configured_permissions: ['jrc_contact_center_monitor'],
                permissions: [],
              },
            ],
          },
        }),
      },
    });
    const wrapper = setup();
    await flushPromises();
    await wrapper.get('[data-edit-authority="9"]').trigger('click');
    await flushPromises();
    expect(wrapper.get('[data-inactive-team-origins]').text()).toContain(
      'SYNTHETIC inactive team'
    );
    expect(
      wrapper
        .find('[data-inherited-origin="jrc_contact_center_monitor"]')
        .exists()
    ).toBe(false);
  });
});
