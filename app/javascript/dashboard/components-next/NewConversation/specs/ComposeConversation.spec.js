import { computed, reactive } from 'vue';
import { mount, shallowMount, flushPromises } from '@vue/test-utils';
import { useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { fetchContactableInboxes } from '../helpers/composeConversationHelper';
import ComposeConversation from '../ComposeConversation.vue';
import ComposeNewConversationForm from '../components/ComposeNewConversationForm.vue';
import NativePopover from 'dashboard/components-next/popover/Popover.vue';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';

vi.mock('vue-router', () => ({ useRoute: vi.fn() }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/store', () => ({
  useStore: vi.fn(),
  useMapGetter: vi.fn(),
}));
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({ fetchSignatureFlagFromUISettings: () => false }),
}));
vi.mock('dashboard/composables/useKeyboardEvents', () => ({
  useKeyboardEvents: vi.fn(),
}));
vi.mock('../helpers/composeConversationHelper', async importOriginal => ({
  ...(await importOriginal()),
  fetchContactableInboxes: vi.fn(),
}));

const hide = vi.fn();
const Popover = {
  name: 'Popover',
  emits: ['show', 'hide'],
  setup(_props, { expose }) {
    expose({ hide });
  },
  template: '<div><slot /><slot name="content" /></div>',
};
let wrapper;
let route;
let store;
const mountComposer = props => {
  wrapper = shallowMount(ComposeConversation, {
    props,
    global: { stubs: { Popover } },
  });
};
const form = () => wrapper.findComponent(ComposeNewConversationForm);

beforeEach(() => {
  vi.clearAllMocks();
  route = reactive({ params: { accountId: '7' } });
  useRoute.mockReturnValue(route);
  store = {
    getters: { getCurrentUserID: 25 },
    dispatch: vi.fn().mockResolvedValue({ account_id: 7, id: 42 }),
  };
  useStore.mockReturnValue(store);
  const values = {
    'contacts/getContactById': () => null,
    'contacts/getUIFlags': {},
    getCurrentUser: { id: 25 },
    'globalConfig/get': { directUploadsEnabled: false },
    'contactConversations/getUIFlags': { isCreating: false },
    getMessageSignature: '',
    'inboxes/getInboxes': [],
  };
  useMapGetter.mockImplementation(name => computed(() => values[name]));
});
afterEach(() => {
  wrapper?.unmount();
  document.body.innerHTML = '';
});

it('keeps the composer open while its native contact dialog is being used', async () => {
  wrapper = mount(NativePopover, {
    props: { modal: true },
    slots: {
      default: '<button>Compose</button>',
      content: '<div>Message</div>',
    },
    attachTo: document.body,
  });
  await wrapper.vm.show();
  await flushPromises();
  const dialog = document.createElement('dialog');
  dialog.setAttribute('open', '');
  dialog.setAttribute('data-popover-content', '');
  document.body.append(dialog);
  dialog.dispatchEvent(new MouseEvent('pointerdown', { bubbles: true }));
  dialog.dispatchEvent(new MouseEvent('click', { bubbles: true }));
  const escape = useKeyboardEvents.mock.calls.at(-1)[0].Escape.action;
  escape();
  await flushPromises();
  expect(wrapper.emitted('hide')).toBeUndefined();
  expect(document.querySelector('[data-popover-backdrop]')).not.toBeNull();
  dialog.remove();
  escape();
  await flushPromises();
  expect(wrapper.emitted('hide')).toHaveLength(1);
});

it('preserves the generic native conversation creation when no proposal adapter is provided', async () => {
  mountComposer({});
  const payload = { contactId: 11, inboxId: 18, message: { content: 'Hello' } };
  form().vm.$emit('createConversation', { payload, isFromWhatsApp: false });
  await flushPromises();
  expect(store.dispatch).toHaveBeenCalledWith('contactConversations/create', {
    params: payload,
    isFromWhatsApp: false,
  });
  expect(hide).toHaveBeenCalledOnce();
  expect(useAlert.mock.calls[0][1].to).toBe('/app/accounts/7/conversations/42');
});

it('keeps recipient and message state after a proposal adapter fails, then closes only on success', async () => {
  const submitHandler = vi.fn().mockResolvedValue(false);
  mountComposer({ submitHandler, initialMessage: 'Proposal link' });
  form().vm.$emit('createConversation', {
    payload: { contactId: 11 },
    isFromWhatsApp: false,
  });
  await flushPromises();
  expect(hide).not.toHaveBeenCalled();
  expect(form().props('formState').message).toBe('Proposal link');
  expect(store.dispatch).not.toHaveBeenCalled();
  const result = { proposal: { id: 31 } };
  submitHandler.mockResolvedValue(result);
  form().vm.$emit('createConversation', {
    payload: { contactId: 11 },
    isFromWhatsApp: false,
  });
  await flushPromises();
  expect(hide).toHaveBeenCalledOnce();
  expect(wrapper.emitted('submitted')).toEqual([[result]]);
});

it('does not replace the latest recipient inboxes with an older asynchronous lookup', async () => {
  let finishFirst;
  fetchContactableInboxes.mockReturnValueOnce(
    new Promise(resolve => {
      finishFirst = resolve;
    })
  );
  fetchContactableInboxes.mockResolvedValueOnce([
    { id: 18, name: 'WhatsApp B', channelType: 'Channel::Whatsapp' },
  ]);
  mountComposer({
    inboxFilter: inbox => inbox.channelType === 'Channel::Whatsapp',
  });
  const first = wrapper.vm.selectContact({ id: 11, name: 'A' });
  await wrapper.vm.selectContact({ id: 12, name: 'B' });
  finishFirst([{ id: 19, name: 'Other inbox', channelType: 'Channel::Email' }]);
  await first;
  await flushPromises();
  expect(form().props('selectedContact')).toMatchObject({
    id: 12,
    name: 'B',
    contactInboxes: [{ id: 18 }],
  });
});

it('clears and invalidates a pending recipient lookup after changing account', async () => {
  let finish;
  fetchContactableInboxes.mockReturnValue(
    new Promise(resolve => {
      finish = resolve;
    })
  );
  mountComposer({});
  const selected = wrapper.vm.selectContact({ id: 11, name: 'A' });
  route.params.accountId = '8';
  await flushPromises();
  finish([{ id: 18, channelType: 'Channel::Whatsapp' }]);
  await selected;
  expect(form().props('selectedContact')).toBeNull();
});
