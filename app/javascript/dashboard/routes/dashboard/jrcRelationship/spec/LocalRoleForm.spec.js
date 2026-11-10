import { mount, flushPromises } from '@vue/test-utils';
import { reactive } from 'vue';
import { createStore } from 'vuex';
import { beforeEach, afterEach, describe, expect, it, vi } from 'vitest';
import LocalRoleForm from '../LocalRoleForm.vue';
import { localRoleDraft } from '../localRoleDraft';
import API from 'dashboard/api/jrcRelationship';

let route;
vi.mock('vue-router', () => ({ useRoute: () => route }));
vi.mock('dashboard/api/jrcRelationship', () => ({
  default: { localRoleOptions: vi.fn() },
}));

let wrapper;
let original;
const options = {
  data: {
    payload: [
      { id: 17, name: 'Synthetic active member', active: true },
      { id: 18, name: 'Synthetic inactive member', active: false },
    ],
    meta: { total: 26 },
  },
};

beforeEach(() => {
  vi.resetAllMocks();
  route = reactive({ params: { accountId: '1' } });
  original = localRoleDraft(null);
  original.enabled = true;
  API.localRoleOptions.mockResolvedValue(options);
});
afterEach(() => wrapper?.unmount());

describe('explicit local role membership form', () => {
  const render = async (disabled = false) => {
    const store = createStore({
      getters: {
        getCurrentUserID: () => 7,
        getCurrentRole: () => 'administrator',
        getCurrentUser: () => ({
          accounts: [{ id: 1, role: 'administrator' }],
        }),
      },
    });
    wrapper = mount(LocalRoleForm, {
      props: { modelValue: original, scopeKey: 'account', disabled },
      global: { plugins: [store] },
    });
    await flushPromises();
  };

  it('loads only explicit account/scope options without assigning a role', async () => {
    await render();
    expect(API.localRoleOptions).toHaveBeenCalledWith(
      '1',
      { scope_key: 'account', page: 1, q: '' },
      expect.any(Object)
    );
    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
    expect(original.members).toEqual([]);
  });

  it('adds the selected analyst without automatic independent document or export grants', async () => {
    await render();
    await wrapper.get('[data-testid="local-role-member"]').setValue('17');
    await wrapper.get('[data-testid="local-role-add"]').trigger('click');
    const [draft] = wrapper.emitted('update:modelValue').at(-1);
    expect(draft.members).toEqual([
      { user_id: 17, role: 'analyst', grants: [], document_categories: [] },
    ]);
    expect(original.members).toEqual([]);
  });

  it('prevents choosing an inactive account member', async () => {
    await render();
    expect(
      wrapper.get('option[value="18"]').attributes('disabled')
    ).toBeDefined();
    expect(
      wrapper.get('[data-testid="local-role-add"]').attributes('disabled')
    ).toBeDefined();
  });

  it('does not publish membership changes from a disabled form', async () => {
    await render();
    await wrapper.get('[data-testid="local-role-member"]').setValue('17');
    await wrapper.setProps({ disabled: true });
    await wrapper.get('[data-testid="local-role-add"]').trigger('click');
    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
  });

  it('clears a selected person when requesting the next options page', async () => {
    await render();
    await wrapper.get('[data-testid="local-role-member"]').setValue('17');
    API.localRoleOptions.mockResolvedValueOnce({
      data: {
        payload: [{ id: 27, name: 'Synthetic next page', active: true }],
        meta: { total: 26 },
      },
    });
    await wrapper.get('[data-testid="local-role-next"]').trigger('click');
    await flushPromises();
    expect(API.localRoleOptions).toHaveBeenLastCalledWith(
      '1',
      { scope_key: 'account', page: 2, q: '' },
      expect.any(Object)
    );
    expect(
      wrapper.get('[data-testid="local-role-member"]').element.value
    ).not.toBe('17');
    expect(
      wrapper.get('[data-testid="local-role-add"]').attributes('disabled')
    ).toBeDefined();
  });

  it('never displays a late options response from the previous account', async () => {
    let resolve;
    API.localRoleOptions.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    await render();
    API.localRoleOptions.mockResolvedValueOnce({
      data: {
        payload: [{ id: 27, name: 'Synthetic second account', active: true }],
        meta: { total: 1 },
      },
    });
    route.params.accountId = '2';
    await flushPromises();
    resolve(options);
    await flushPromises();
    expect(wrapper.find('option[value="17"]').exists()).toBe(false);
    expect(wrapper.get('option[value="27"]').text()).toBe(
      'Synthetic second account'
    );
    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
  });
});
