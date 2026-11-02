import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import CampaignWizard from '../components/CampaignWizard.vue';
import api from 'dashboard/api/jrcCampaigns';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/routes/dashboard/jrcCustomers/useCustomerMaster', () => ({
  useCustomerMaster: () => ({ enabled: false }),
}));
vi.mock('dashboard/api/jrcCampaigns', () => ({
  default: { audiencePreview: vi.fn() },
}));
enableAutoUnmount(afterEach);

const sender = {
  id: 8,
  name: 'Synthetic sender A',
  connector: 'broker',
  health_status: 'CONNECTED',
};
const otherSender = { ...sender, id: 9, name: 'Synthetic sender B' };
const global = { mocks: { $t: key => key } };

describe('explicit campaign sender selection', () => {
  beforeEach(() => {
    api.audiencePreview.mockResolvedValue({
      data: { estimated_recipients: 1, sample: [] },
    });
  });

  it('requires choosing the sender even when only one connected inbox exists', async () => {
    const wrapper = mount(CampaignWizard, {
      props: { metadata: { whatsapp_inboxes: [sender] } },
      global,
    });
    wrapper.vm.stepIndex = 1;
    await flushPromises();

    expect(wrapper.get('input[type="checkbox"]').element.checked).toBe(false);
    expect(wrapper.vm.configValid).toBe(false);
    expect(wrapper.vm.buildPayload().campaign_inboxes_attributes).toEqual([]);
  });

  it('preserves an explicit deselection when sender metadata refreshes', async () => {
    const wrapper = mount(CampaignWizard, {
      props: { metadata: { whatsapp_inboxes: [sender] } },
      global,
    });
    wrapper.vm.stepIndex = 1;
    await flushPromises();
    await wrapper.get('input[type="checkbox"]').setValue(true);
    await wrapper.get('input[type="checkbox"]').setValue(false);
    await wrapper.setProps({
      metadata: { whatsapp_inboxes: [{ ...sender }] },
    });

    expect(wrapper.get('input[type="checkbox"]').element.checked).toBe(false);
    expect(wrapper.vm.configValid).toBe(false);
    expect(wrapper.vm.buildPayload().campaign_inboxes_attributes).toEqual([]);
  });

  it('keeps the chosen sender when a refreshed list changes its order', async () => {
    const wrapper = mount(CampaignWizard, {
      props: { metadata: { whatsapp_inboxes: [sender, otherSender] } },
      global,
    });
    wrapper.vm.stepIndex = 1;
    await flushPromises();
    await wrapper
      .findAll('label')
      .find(label => label.text().includes('Synthetic sender A'))
      .get('input[type="checkbox"]')
      .setValue(true);
    await wrapper.setProps({
      metadata: { whatsapp_inboxes: [otherSender, { ...sender }] },
    });

    expect(wrapper.vm.buildPayload().campaign_inboxes_attributes).toEqual([
      expect.objectContaining({ inbox_id: 8, position: 0, enabled: true }),
    ]);
    expect(wrapper.vm.configValid).toBe(true);
  });

  it('requires a new choice when the selected inbox disappears without substituting the remaining sender', async () => {
    const wrapper = mount(CampaignWizard, {
      props: { metadata: { whatsapp_inboxes: [sender, otherSender] } },
      global,
    });
    wrapper.vm.stepIndex = 1;
    await flushPromises();
    await wrapper
      .findAll('label')
      .find(label => label.text().includes('Synthetic sender A'))
      .get('input[type="checkbox"]')
      .setValue(true);
    await wrapper.setProps({
      metadata: { whatsapp_inboxes: [otherSender] },
    });

    expect(wrapper.get('input[type="checkbox"]').element.checked).toBe(false);
    expect(wrapper.vm.configValid).toBe(false);
    expect(wrapper.vm.buildPayload().campaign_inboxes_attributes).toEqual([]);
  });
});
