import { mount, flushPromises } from '@vue/test-utils';
import { reactive } from 'vue';
import { createStore } from 'vuex';
import { routeLocationKey } from 'vue-router';
import { beforeEach, afterEach, it, expect, vi } from 'vitest';
import LeadCreateModal from '../LeadCreateModal.vue';
import { leadsAPI } from 'dashboard/api/crm';
import { useAlert } from 'dashboard/composables';
import { draftKey, readDraft, saveDraft } from '../../../helpers/formDrafts';

vi.mock('dashboard/api/crm', () => ({ leadsAPI: { create: vi.fn() } }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
let wrapper;
let authority;
let route;
const ownerKey = draftKey(1, 7, 'crm:new_lead:141');
beforeEach(() => {
  vi.resetAllMocks();
  sessionStorage.clear();
  authority = reactive({
    account: 1,
    user: 7,
    role: 'administrator',
    grant: 1,
  });
  route = reactive({ params: { accountId: '1' } });
  const store = createStore({
    getters: {
      getCurrentAccountId: () => authority.account,
      getCurrentUserID: () => authority.user,
      getCurrentRole: () => authority.role,
      getCurrentUser: () => ({
        id: authority.user,
        accounts: [
          {
            id: authority.account,
            role: authority.role,
            custom_role_id: authority.grant,
          },
        ],
      }),
      'accounts/isFeatureEnabledonAccount': () => () => false,
    },
  });
  wrapper = mount(LeadCreateModal, {
    props: {
      contact: {
        id: 141,
        name: 'Synthetic private contact',
        email: 'private@example.test',
      },
    },
    global: {
      plugins: [store],
      provide: { [routeLocationKey]: route },
      stubs: { Teleport: true },
    },
  });
});
afterEach(() => wrapper.unmount());

it('hides a role-invalidated standalone form and preserves its original owner draft', async () => {
  await wrapper.get('[name="notes"]').setValue('Synthetic original draft');
  const oldForm = wrapper.get('form');
  authority.role = 'agent';
  await flushPromises();
  expect(wrapper.find('form').exists()).toBe(false);
  expect(wrapper.text()).not.toContain('Synthetic private contact');
  expect(wrapper.emitted('close')).toHaveLength(1);
  expect(readDraft(ownerKey).form.notes).toBe('Synthetic original draft');
  await oldForm.trigger('submit');
  await flushPromises();
  expect(leadsAPI.create).not.toHaveBeenCalled();
});

it('does not revive an old form or move its contact draft into a replacement account', async () => {
  await wrapper.get('[name="notes"]').setValue('Synthetic account one note');
  authority.account = 2;
  route.params.accountId = '2';
  await flushPromises();
  expect(wrapper.find('form').exists()).toBe(false);
  expect(readDraft(ownerKey).form.notes).toBe('Synthetic account one note');
  expect(readDraft(draftKey(2, 7, 'crm:new_lead:141'))).toBeNull();
  authority.account = 1;
  route.params.accountId = '1';
  await flushPromises();
  expect(wrapper.find('form').exists()).toBe(false);
});

it('ignores a successful native creation after grants changed and retains the old draft without resending', async () => {
  let finish;
  leadsAPI.create.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  await wrapper.get('[name="notes"]').setValue('Synthetic pending note');
  await wrapper.get('form').trigger('submit');
  authority.grant = 2;
  await flushPromises();
  finish({ status: 201, data: { id: 22, contact_id: 141 } });
  await flushPromises();
  expect(wrapper.emitted('created')).toBeUndefined();
  expect(useAlert).not.toHaveBeenCalled();
  expect(readDraft(ownerKey).form.notes).toBe('Synthetic pending note');
  expect(leadsAPI.create).toHaveBeenCalledTimes(1);
});

it('does not emit a success or clear the existing draft after unmount while its native creation finishes', async () => {
  let finish;
  leadsAPI.create.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  await wrapper.get('[name="notes"]').setValue('Synthetic unmounted note');
  await wrapper.get('form').trigger('submit');
  wrapper.unmount();
  finish({ status: 201, data: { id: 22, contact_id: 141 } });
  await flushPromises();
  expect(useAlert).not.toHaveBeenCalled();
  expect(wrapper.emitted('created')).toBeUndefined();
  expect(readDraft(ownerKey).form.notes).toBe('Synthetic unmounted note');
});

it('does not display an obsolete private conflict after actor replacement', async () => {
  let fail;
  leadsAPI.create.mockImplementationOnce(
    () =>
      new Promise((_resolve, reject) => {
        fail = reject;
      })
  );
  await wrapper.get('form').trigger('submit');
  authority.user = 99;
  await flushPromises();
  fail({
    response: {
      status: 409,
      data: { errors: ['Synthetic previous actor conflict'] },
    },
  });
  await flushPromises();
  expect(wrapper.text()).not.toContain('Synthetic previous actor conflict');
  expect(wrapper.find('form').exists()).toBe(false);
  expect(useAlert).not.toHaveBeenCalled();
});

it('completes only the current native owner draft after success, preserving another existing draft', async () => {
  const otherKey = draftKey(2, 99, 'crm:new_lead:141');
  saveDraft(otherKey, { form: { notes: 'Synthetic unrelated draft' } });
  leadsAPI.create.mockResolvedValueOnce({
    status: 201,
    data: { id: 22, contact_id: 141 },
  });
  await wrapper.get('[name="notes"]').setValue('Synthetic current note');
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  expect(wrapper.emitted('created')[0][0]).toEqual({ id: 22, contact_id: 141 });
  expect(useAlert).toHaveBeenCalledTimes(1);
  expect(readDraft(ownerKey)).toBeNull();
  expect(readDraft(otherKey).form.notes).toBe('Synthetic unrelated draft');
});
