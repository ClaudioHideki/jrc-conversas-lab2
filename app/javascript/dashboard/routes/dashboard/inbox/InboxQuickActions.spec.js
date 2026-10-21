import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import CannedAPI from 'dashboard/api/cannedResponse';
import LabelsAPI from 'dashboard/api/labels';
import ConversationAPI from 'dashboard/api/conversations';
import InboxQuickActions from './InboxQuickActions.vue';
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/api/cannedResponse', () => ({ default: { get: vi.fn() } }));
vi.mock('dashboard/api/labels', () => ({ default: { get: vi.fn() } }));
vi.mock('dashboard/api/conversations', () => ({
  default: { getLabels: vi.fn(), updateLabels: vi.fn() },
}));
enableAutoUnmount(afterEach);
const global = {
  stubs: { TeleportWithDirection: { template: '<div><slot /></div>' } },
};
describe('configured quick actions', () => {
  beforeEach(() => {
    HTMLDialogElement.prototype.showModal = vi.fn();
    HTMLDialogElement.prototype.close = vi.fn();
    CannedAPI.get.mockResolvedValue({
      data: [
        {
          id: 1,
          short_code: 'configured-greeting',
          content: 'A configured reply',
        },
        { id: 2, short_code: 'order', content: 'Order update' },
      ],
    });
    LabelsAPI.get.mockResolvedValue({
      data: { payload: [{ id: 4, title: 'configured-qualification' }] },
    });
    ConversationAPI.getLabels.mockResolvedValue({
      data: { payload: ['already-present'] },
    });
    ConversationAPI.updateLabels.mockResolvedValue({
      data: { payload: ['already-present', 'configured-qualification'] },
    });
  });
  it('searches native canned replies and inserts a draft without sending', async () => {
    const wrapper = mount(InboxQuickActions, {
      props: { accountId: 1, conversationId: 101 },
      global,
    });
    await wrapper.vm.open('REPLIES');
    await flushPromises();
    expect(CannedAPI.get).toHaveBeenCalledWith({ searchKey: '' });
    await wrapper.get('input').setValue('configured-greeting');
    expect(wrapper.text()).not.toContain('Order update');
    await wrapper
      .findAll('button')
      .find(button => button.text().includes('configured-greeting'))
      .trigger('click');
    expect(wrapper.emitted('insert')).toEqual([['A configured reply']]);
    expect(ConversationAPI.updateLabels).not.toHaveBeenCalled();
  });
  it('adds a configured native label while preserving existing labels', async () => {
    const wrapper = mount(InboxQuickActions, {
      props: { accountId: 1, conversationId: 101 },
      global,
    });
    await wrapper.vm.open('QUALIFICATIONS');
    await flushPromises();
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'configured-qualification')
      .trigger('click');
    await flushPromises();
    expect(ConversationAPI.updateLabels).toHaveBeenCalledWith(101, [
      'already-present',
      'configured-qualification',
    ]);
    expect(wrapper.emitted('qualify')).toEqual([['configured-qualification']]);
  });
  it('uses existing occurrence categories for voice without a new domain or label mutation', async () => {
    const wrapper = mount(InboxQuickActions, {
      props: {
        accountId: 1,
        callId: 7,
        categories: ['Existing case category'],
      },
      global,
    });
    await wrapper.vm.open('QUALIFICATIONS');
    await flushPromises();
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'Existing case category')
      .trigger('click');
    expect(wrapper.emitted('qualify')).toEqual([['Existing case category']]);
    expect(LabelsAPI.get).not.toHaveBeenCalled();
    expect(ConversationAPI.updateLabels).not.toHaveBeenCalled();
  });
  it('shows an empty configuration without introducing fixed operational choices', async () => {
    CannedAPI.get.mockResolvedValue({ data: [] });
    const wrapper = mount(InboxQuickActions, {
      props: { accountId: 1, conversationId: 101 },
      global,
    });
    await wrapper.vm.open('REPLIES');
    await flushPromises();
    expect(wrapper.text()).toContain(
      'JRC_CONTACT_CENTER.INBOX_360.OPTIONS_EMPTY'
    );
    expect(wrapper.emitted('insert')).toBeUndefined();
  });
  it('discards a late canned reply after changing Account and interaction', async () => {
    let resolveOld;
    CannedAPI.get.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolveOld = resolve;
        })
    );
    const wrapper = mount(InboxQuickActions, {
      props: { accountId: 1, conversationId: 101 },
      global,
    });
    const pending = wrapper.vm.open('REPLIES');
    await wrapper.setProps({ accountId: 2, conversationId: 202 });
    resolveOld({
      data: [{ id: 1, short_code: 'A-only', content: 'Account A content' }],
    });
    await pending;
    await flushPromises();
    expect(wrapper.text()).not.toContain('Account A content');
    expect(wrapper.emitted('insert')).toBeUndefined();
  });
  it('does not report successful qualification when the native API rejects it', async () => {
    ConversationAPI.updateLabels.mockRejectedValue(new Error('403'));
    const wrapper = mount(InboxQuickActions, {
      props: { accountId: 1, conversationId: 101 },
      global,
    });
    await wrapper.vm.open('QUALIFICATIONS');
    await flushPromises();
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'configured-qualification')
      .trigger('click');
    await flushPromises();
    expect(wrapper.emitted('qualify')).toBeUndefined();
    expect(wrapper.get('[role="alert"]').text()).toBe(
      'JRC_CONTACT_CENTER.COMMON.ERROR'
    );
  });
});
