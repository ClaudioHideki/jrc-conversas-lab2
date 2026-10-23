import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { reactive } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import locale from 'dashboard/i18n/locale/en/jrcServiceDesk.json';
import InteractionComposer from '../InteractionComposer.vue';
import {
  contextPayload,
  deferred,
  ticket as makeTicket,
} from '../../__tests__/fixtures';

const mocks = vi.hoisted(() => ({
  session: null,
  composer: vi.fn(),
  preview: vi.fn(),
  interaction: vi.fn(),
  read: vi.fn(),
}));
vi.mock('dashboard/api/serviceDeskCockpit', () => ({ default: mocks }));
vi.mock('../../composables/useServiceDesk', () => ({
  useServiceDesk: () => mocks.session,
}));

const labels = locale.JRC_SERVICE_DESK;
const ticket = makeTicket({ lock_version: 0, team: { id: '7' } });
const choices = (
  audiences = [
    'internal',
    'technical_team',
    'customer',
    'public_without_notification',
  ]
) => ({
  contract_version: 1,
  account_id: ticket.account_id,
  composer: {
    account_id: ticket.account_id,
    unit_id: ticket.unit_id,
    ticket_id: ticket.id,
    audiences,
    recipient: { id: '6', name: 'Authorized customer' },
    channels: [
      {
        channel: 'email',
        available: true,
        destinations: [
          {
            conversation_id: '8',
            recipient: 'customer@example.test',
            available: true,
            reason: null,
          },
        ],
      },
      {
        channel: 'whatsapp',
        available: false,
        reason: 'no_authorized_conversation',
        destinations: [],
      },
    ],
  },
});
const preview = submitted => ({
  contract_version: 1,
  account_id: ticket.account_id,
  preview: {
    account_id: ticket.account_id,
    unit_id: ticket.unit_id,
    ticket_id: ticket.id,
    body: submitted.body,
    audience: submitted.visibility,
    receipt: 'reviewed-literal-content',
    expires_at: new Date(Date.now() + 300000).toISOString(),
    can_publish: true,
    deliveries: [],
  },
});
const readback = submitted => ({
  contract_version: 1,
  account_id: ticket.account_id,
  ticket: { id: ticket.id, unit_id: ticket.unit_id },
  cockpit: {
    notes: [
      {
        id: '9',
        account_id: ticket.account_id,
        unit_id: ticket.unit_id,
        ticket_id: ticket.id,
        permissions: { show: true },
        body: submitted.body,
        visibility: submitted.visibility,
        author: null,
        attachments: [],
        deliveries: [],
      },
    ],
    tasks: [],
    approvals: [],
    events: [],
    conversations: [],
    approvers: [],
    incident: null,
  },
});
const wrappers = [];
const mountComposer = (mode, extra = {}) => {
  const wrapper = mount(InteractionComposer, {
    props: { ticket, mode, ...extra },
  });
  wrappers.push(wrapper);
  return wrapper;
};
const button = (wrapper, label) => {
  const found = wrapper
    .findAll('button')
    .find(element => element.text() === label);
  expect(found, 'Missing button: ' + label).toBeDefined();
  return found;
};
const audiences = wrapper =>
  wrapper
    .get('select')
    .findAll('option')
    .map(option => option.element.value);
const reviewAndPublish = async wrapper => {
  await button(wrapper, labels.R2.review).trigger('click');
  await flushPromises();
  await wrapper.get('form').trigger('submit');
  await flushPromises();
};

beforeEach(() => {
  vi.clearAllMocks();
  mocks.session = reactive({
    state: { status: 'ready', context: contextPayload() },
  });
  mocks.composer.mockResolvedValue(choices());
  mocks.preview.mockImplementation(async (_account, _ticket, submitted) =>
    preview(submitted)
  );
  let saved;
  mocks.interaction.mockImplementation(async (_account, _ticket, submitted) => {
    saved = submitted;
    return {
      contract_version: 1,
      applied: true,
      account_id: ticket.account_id,
      ticket_id: ticket.id,
      operation: 'add_interaction',
      result_id: '9',
    };
  });
  mocks.read.mockImplementation(async () => readback(saved));
});
afterEach(() => {
  wrappers.splice(0).forEach(wrapper => {
    if (!wrapper.vm.$.isUnmounted) wrapper.unmount();
  });
});

describe('composer mode follows the current screen and server audience grants', () => {
  it('publishes a technical note within the private mode without selecting external destinations', async () => {
    const wrapper = mountComposer('internal');
    await flushPromises();
    expect(audiences(wrapper)).toEqual(['internal', 'technical_team']);
    expect(wrapper.find('input[type="checkbox"]').exists()).toBe(false);
    await wrapper.get('select').setValue('technical_team');
    await wrapper
      .get('textarea')
      .setValue('Private diagnosis for the technical team');
    expect(wrapper.find('button[type="submit"]').exists()).toBe(false);
    await reviewAndPublish(wrapper);
    const submitted = mocks.interaction.mock.lastCall[2];
    expect(submitted).toEqual({
      body: 'Private diagnosis for the technical team',
      visibility: 'technical_team',
      audience_team_id: '7',
      notification_channels: [],
      notification_conversations: {},
    });
    expect(mocks.interaction.mock.lastCall[6]).toBe('reviewed-literal-content');
    expect(mocks.read).toHaveBeenCalledOnce();
    expect(wrapper.emitted('updated')?.[0]?.[0].outcome).toBe('saved');
  });

  it('requires an explicit available channel and recipient before reviewing a public reply', async () => {
    const wrapper = mountComposer('conversation');
    await flushPromises();
    expect(audiences(wrapper)).toEqual([
      'customer',
      'public_without_notification',
    ]);
    await wrapper.get('textarea').setValue('Reviewed response to the customer');
    expect(button(wrapper, labels.R2.review).element.disabled).toBe(true);
    expect(wrapper.findAll('input[type="checkbox"]')[1].element.disabled).toBe(
      true
    );
    await wrapper.findAll('input[type="checkbox"]')[0].setValue(true);
    expect(button(wrapper, labels.R2.review).element.disabled).toBe(true);
    await wrapper.findAll('select')[1].setValue('8');
    expect(button(wrapper, labels.R2.review).element.disabled).toBe(false);
    expect(mocks.preview).not.toHaveBeenCalled();
    await reviewAndPublish(wrapper);
    expect(mocks.interaction.mock.lastCall[2]).toEqual({
      body: 'Reviewed response to the customer',
      visibility: 'customer',
      notification_channels: ['email'],
      notification_conversations: { email: '8' },
    });
    expect(wrapper.emitted('updated')).toHaveLength(1);
  });

  it('clears selected delivery targets when switching a reply to publication without notification', async () => {
    const wrapper = mountComposer('conversation');
    await flushPromises();
    await wrapper.get('textarea').setValue('Portal update');
    await wrapper.findAll('input[type="checkbox"]')[0].setValue(true);
    await wrapper.findAll('select')[1].setValue('8');
    await wrapper.get('select').setValue('public_without_notification');
    expect(wrapper.find('input[type="checkbox"]').exists()).toBe(false);
    await reviewAndPublish(wrapper);
    expect(mocks.preview.mock.lastCall[2]).toMatchObject({
      visibility: 'public_without_notification',
      notification_channels: [],
      notification_conversations: {},
    });
    expect(mocks.interaction.mock.lastCall[2]).toMatchObject({
      visibility: 'public_without_notification',
      notification_channels: [],
      notification_conversations: {},
    });
    expect(wrapper.emitted('updated')).toHaveLength(1);
  });

  it('clears private draft and its approved preview when the component switches to the reply screen', async () => {
    const wrapper = mountComposer('internal');
    await flushPromises();
    await wrapper
      .get('textarea')
      .setValue('Do not send this private diagnosis');
    await button(wrapper, labels.R2.review).trigger('click');
    await flushPromises();
    expect(wrapper.find('button[type="submit"]').exists()).toBe(true);
    await wrapper.setProps({ mode: 'conversation' });
    await flushPromises();
    expect(wrapper.get('textarea').element.value).toBe('');
    expect(wrapper.text()).not.toContain('Do not send this private diagnosis');
    expect(wrapper.find('button[type="submit"]').exists()).toBe(false);
    expect(audiences(wrapper)).toEqual([
      'customer',
      'public_without_notification',
    ]);
    await wrapper.get('form').trigger('submit');
    expect(mocks.interaction).not.toHaveBeenCalled();
  });

  it('does not invent a public audience when the server only grants internal writing', async () => {
    mocks.composer.mockResolvedValue(choices(['internal']));
    const wrapper = mountComposer('conversation');
    await flushPromises();
    expect(audiences(wrapper)).toEqual([]);
    await wrapper
      .get('textarea')
      .setValue('Cannot be published from this screen');
    expect(button(wrapper, labels.R2.review).element.disabled).toBe(true);
    await wrapper.get('form').trigger('submit');
    expect(mocks.preview).not.toHaveBeenCalled();
    expect(mocks.interaction).not.toHaveBeenCalled();
  });

  it('ignores an internal review response that arrives after switching to a public composer', async () => {
    const pending = deferred();
    mocks.preview.mockReturnValueOnce(pending.promise);
    const wrapper = mountComposer('internal');
    await flushPromises();
    await wrapper.get('textarea').setValue('Private pending content');
    await button(wrapper, labels.R2.review).trigger('click');
    await flushPromises();
    await wrapper.setProps({ mode: 'conversation' });
    await flushPromises();
    pending.resolve(
      preview({ body: 'Private pending content', visibility: 'internal' })
    );
    await flushPromises();
    expect(wrapper.text()).not.toContain('Private pending content');
    expect(wrapper.find('button[type="submit"]').exists()).toBe(false);
    expect(mocks.interaction).not.toHaveBeenCalled();
  });

  it('restricts the file screen to non-notifying audiences and blocks empty attachments before review', async () => {
    const wrapper = mountComposer('files');
    await flushPromises();
    expect(audiences(wrapper)).toEqual([
      'internal',
      'technical_team',
      'public_without_notification',
    ]);
    const input = wrapper.get('input[type="file"]');
    Object.defineProperty(input.element, 'files', {
      configurable: true,
      value: [new File([], 'empty.txt')],
    });
    await input.trigger('change');
    expect(wrapper.get('textarea').element.value).toBe(
      labels.REDESIGN_DETAIL.attached_files
    );
    expect(wrapper.get('[role="alert"]').text()).toBe(
      labels.REDESIGN_DETAIL.invalid_files
    );
    expect(button(wrapper, labels.R2.review).element.disabled).toBe(true);
    expect(mocks.preview).not.toHaveBeenCalled();
    await button(wrapper, labels.REDESIGN_DETAIL.remove_selection).trigger(
      'click'
    );
    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
    expect(wrapper.text()).not.toContain('empty.txt');
  });
});
