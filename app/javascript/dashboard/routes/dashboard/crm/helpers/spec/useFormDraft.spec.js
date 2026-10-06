import { defineComponent, reactive, ref } from 'vue';
import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { useRoute } from 'vue-router';
import { useFormDraft } from '../useFormDraft';
import { draftKey, readDraft, saveDraft } from '../formDrafts';

vi.mock('vue-router', () => ({ useRoute: vi.fn() }));

it('ACCOUNT-01 scopes restoration and in-flight save completion to the original account and user', () => {
  const route = reactive({ params: { accountId: '1' } });
  const user = reactive({ id: 25 });
  useRoute.mockReturnValue(route);
  const oldKey = draftKey(1, 25, 'crm:test');
  const newKey = draftKey(2, 25, 'crm:test');
  saveDraft(newKey, { title: 'Outra account' });
  let form;
  let draft;
  let active;
  const component = defineComponent({
    setup() {
      form = reactive({ title: '' });
      active = ref(true);
      draft = useFormDraft('crm:test', {
        active, snapshot: () => ({ ...form }), restore: value => Object.assign(form, value),
        reset: () => { form.title = ''; },
      });
      draft.open();
      return () => null;
    },
  });
  const wrapper = mount(component, { global: { plugins: [createStore({ getters: { getCurrentUser: () => user } })] } });
  form.title = 'Account original';
  const requestKey = draft.key.value;
  route.params.accountId = '2';
  expect(active.value).toBe(false);
  expect(form.title).toBe('');
  expect(readDraft(oldKey).title).toBe('Account original');
  expect(draft.complete(requestKey)).toBe(false);
  expect(readDraft(oldKey)).toBeNull();
  expect(readDraft(newKey).title).toBe('Outra account');
  draft.open();
  expect(form.title).toBe('Outra account');
  active.value = true;
  user.id = 26;
  expect(form.title).toBe('');
  expect(active.value).toBe(false);
  expect(readDraft(draft.key.value)).toBeNull();
  wrapper.unmount();
});
