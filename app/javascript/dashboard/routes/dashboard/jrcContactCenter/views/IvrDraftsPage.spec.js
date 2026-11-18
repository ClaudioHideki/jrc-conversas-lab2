import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { h, reactive, ref } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import IvrDraftsPage from './IvrDraftsPage.vue';

let user;
let route;
vi.mock('dashboard/composables/store', () => ({ useMapGetter: () => user }));
vi.mock('vue-router', () => ({ useRoute: () => route }));
vi.mock('../components/IvrDraftWorkspace.vue', () => ({
  default: {
    props: ['accountId'],
    setup(props) {
      const privateDraft = ref('');
      return () =>
        h('input', {
          value: privateDraft.value,
          'data-account': props.accountId,
          onInput: event => {
            privateDraft.value = event.target.value;
          },
        });
    },
  },
}));
enableAutoUnmount(afterEach);
beforeEach(() => {
  route = reactive({ params: { accountId: '1' } });
  user = ref({
    id: 4,
    type: 'User',
    accounts: [
      {
        id: 1,
        role: 'agent',
        custom_role_id: 10,
        permissions: [
          'jrc_contact_center_configure',
          'jrc_contact_center_view',
        ],
      },
    ],
  });
});

describe('native IVR workspace context boundaries', () => {
  it('unmounts a previous account draft instead of reusing its private fields in the next account', async () => {
    const wrapper = mount(IvrDraftsPage);
    await wrapper.get('input').setValue('PRIVATE previous account draft');
    route.params.accountId = '2';
    await flushPromises();
    expect(wrapper.get('input').attributes('data-account')).toBe('2');
    expect(wrapper.get('input').element.value).toBe('');
  });

  it('drops old fields when the authenticated actor or effective profile changes', async () => {
    const wrapper = mount(IvrDraftsPage);
    await wrapper.get('input').setValue('PRIVATE previous profile draft');
    user.value.accounts[0].permissions = [];
    await flushPromises();
    expect(wrapper.get('input').element.value).toBe('');
    await wrapper.get('input').setValue('PRIVATE actor draft');
    user.value.id = 5;
    await flushPromises();
    expect(wrapper.get('input').element.value).toBe('');
  });

  it('does not retain an editable workspace after authentication context is cleared', async () => {
    const wrapper = mount(IvrDraftsPage);
    await wrapper.get('input').setValue('PRIVATE prior authentication');
    user.value = {};
    await flushPromises();
    expect(wrapper.find('input').exists()).toBe(false);
  });
});
