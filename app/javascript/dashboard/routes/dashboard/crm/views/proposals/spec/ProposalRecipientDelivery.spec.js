import { reactive, ref } from 'vue';
import { shallowMount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import { useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { proposalsAPI } from 'dashboard/api/crm';
import messages from 'dashboard/i18n/locale/en/crm.json';
import ProposalRecipientDelivery from '../ProposalRecipientDelivery.vue';

const permissions = ref(['agent', 'jrc_crm']);
const selectContact = vi.fn();
const contactSaved = vi.fn();
const openContact = vi.fn();
vi.mock('vue-router', () => ({ useRoute: vi.fn() }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/crm', () => ({
  proposalsAPI: { sendToRecipient: vi.fn() },
}));
vi.mock('dashboard/composables/usePolicy', () => ({
  usePolicy: () => ({
    checkPermissions: values =>
      values.some(value => permissions.value.includes(value)),
  }),
}));

const Composer = {
  name: 'ComposeConversation',
  props: [
    'submitHandler',
    'initialMessage',
    'inboxFilter',
    'disabled',
    'isSubmitting',
  ],
  emits: ['submitted'],
  setup(_props, { expose }) {
    expose({ selectContact });
  },
  template:
    '<div><slot name="trigger" /><slot name="recipient-actions" /></div>',
};
const ContactDialog = {
  name: 'CreateNewContactDialog',
  emits: ['create'],
  setup(_props, { expose }) {
    expose({ onSuccess: contactSaved, open: openContact });
  },
  template: '<div />',
};

let wrapper;
let route;
let store;
const publicUrl =
  'https://jrc.example/jrc/propostas/7/synthetic-proposal-token';
const payload = {
  contactId: 12,
  inboxId: 18,
  message: { content: 'Proposal ' + publicUrl },
};
const mountDelivery = (props = {}) => {
  store = createStore({ getters: { getCurrentUserID: () => 25 } });
  store.dispatch = vi.fn().mockResolvedValue({
    id: 12,
    name: 'Test recipient',
    phone_number: '+5511998765432',
  });
  wrapper = shallowMount(ProposalRecipientDelivery, {
    props: { proposalId: 31, publicUrl, ...props },
    global: {
      plugins: [store],
      stubs: {
        ComposeConversation: Composer,
        CreateNewContactDialog: ContactDialog,
      },
    },
  });
};
const submit = value =>
  wrapper.findComponent(Composer).props('submitHandler')({ payload: value });

beforeEach(() => {
  vi.clearAllMocks();
  permissions.value = ['agent', 'jrc_crm'];
  route = reactive({ params: { accountId: '7' } });
  useRoute.mockReturnValue(route);
  proposalsAPI.sendToRecipient.mockResolvedValue({
    data: { proposal: { id: 31 }, delivery: { conversation_id: 22 } },
  });
});
afterEach(() => wrapper?.unmount());

it('uses the native contact save flow and selects the new person without sending', async () => {
  mountDelivery();
  await wrapper.get('[data-proposal-create-contact]').trigger('click');
  expect(openContact).toHaveBeenCalledOnce();
  const contact = { name: 'Test recipient', phoneNumber: '+5511998765432' };
  wrapper.findComponent(ContactDialog).vm.$emit('create', contact);
  await flushPromises();
  expect(store.dispatch).toHaveBeenCalledWith('contacts/create', contact);
  expect(contactSaved).toHaveBeenCalledOnce();
  expect(selectContact).toHaveBeenCalledWith({
    id: 12,
    name: 'Test recipient',
    phone_number: '+5511998765432',
  });
  expect(proposalsAPI.sendToRecipient).not.toHaveBeenCalled();
});

it('submits the selected person and inbox through the proposal endpoint, without updating customer links', async () => {
  mountDelivery();
  const data = await submit(payload);
  expect(data.proposal.id).toBe(31);
  expect(proposalsAPI.sendToRecipient).toHaveBeenCalledWith(
    31,
    {
      contact_id: 12,
      inbox_id: 18,
      content: payload.message.content,
      template_params: undefined,
    },
    expect.any(String)
  );
  expect(store.dispatch).not.toHaveBeenCalled();
  expect(wrapper.findComponent(Composer).props('initialMessage')).toContain(
    publicUrl
  );
});

it('keeps the retry key after an error and changes it only for a different delivery intent', async () => {
  mountDelivery();
  proposalsAPI.sendToRecipient.mockRejectedValue({
    response: { data: { errors: ['Channel not allowed'] } },
  });
  expect(await submit(payload)).toBe(false);
  const firstKey = proposalsAPI.sendToRecipient.mock.calls[0][2];
  expect(useAlert).toHaveBeenCalledWith('Channel not allowed');
  expect(await submit(payload)).toBe(false);
  expect(proposalsAPI.sendToRecipient.mock.calls[1][2]).toBe(firstKey);
  await submit({ ...payload, contactId: 13 });
  expect(proposalsAPI.sendToRecipient.mock.calls[2][2]).not.toBe(firstKey);
});

it('blocks double submission and ignores a late success after switching accounts', async () => {
  let finish;
  proposalsAPI.sendToRecipient.mockReturnValue(
    new Promise(resolve => {
      finish = resolve;
    })
  );
  mountDelivery();
  const first = submit(payload);
  expect(await submit(payload)).toBe(false);
  expect(proposalsAPI.sendToRecipient).toHaveBeenCalledOnce();
  route.params.accountId = '8';
  finish({ data: { proposal: { id: 31 } } });
  expect(await first).toBe(false);
  expect(useAlert).not.toHaveBeenCalled();
});

it('filters the native inbox list to supported WhatsApp channels', () => {
  mountDelivery();
  const accepts = wrapper.findComponent(Composer).props('inboxFilter');
  expect(accepts({ channelType: 'Channel::Whatsapp' })).toBe(true);
  expect(
    accepts({ channelType: 'Channel::TwilioSms', medium: 'whatsapp' })
  ).toBe(true);
  expect(
    accepts({ channelType: 'Channel::Api', name: 'WhatsApp integration' })
  ).toBe(true);
  expect(
    accepts({ channelType: 'Channel::Email', name: 'WhatsApp by email' })
  ).toBe(false);
  expect(accepts({ channelType: 'Channel::TwilioSms', medium: 'sms' })).toBe(
    false
  );
});

it('does not offer contact creation or submit for a CRM-only role without native contact access', async () => {
  permissions.value = ['jrc_crm', 'conversation_manage'];
  mountDelivery();
  expect(wrapper.find('[data-proposal-create-contact]').exists()).toBe(false);
  expect(
    wrapper.get('[data-proposal-recipient-trigger]').attributes('disabled')
  ).toBeDefined();
  expect(await submit(payload)).toBe(false);
  expect(proposalsAPI.sendToRecipient).not.toHaveBeenCalled();
});

it('blocks submission while the parent proposal has unsaved or terminal data', async () => {
  mountDelivery({ disabled: true });
  expect(await submit(payload)).toBe(false);
  expect(proposalsAPI.sendToRecipient).not.toHaveBeenCalled();
  expect(
    wrapper.get('[data-proposal-recipient-trigger]').attributes('disabled')
  ).toBeDefined();
  expect(messages.CRM.PROPOSAL_RECIPIENT.ERROR).toBeTruthy();
});
