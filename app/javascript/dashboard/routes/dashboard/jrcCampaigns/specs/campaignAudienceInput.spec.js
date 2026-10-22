import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import CampaignAudienceInput from '../components/CampaignAudienceInput.vue';
import CampaignWizard from '../components/CampaignWizard.vue';
import api from 'dashboard/api/jrcCampaigns';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/api/jrcCampaigns', () => ({
  default: { createSanitizedList: vi.fn(), audiencePreview: vi.fn() },
}));
vi.mock('dashboard/routes/dashboard/jrcCustomers/useCustomerMaster', () => ({
  useCustomerMaster: () => ({ enabled: false }),
}));
enableAutoUnmount(afterEach);

describe('audience input inside the campaign', () => {
  beforeEach(() => {
    api.audiencePreview.mockResolvedValue({
      data: { estimated_recipients: 2, available_recipients: 2, sample: [] },
    });
    api.createSanitizedList.mockResolvedValue({
      data: { id: 42, name: 'Pilot', stats: { valid_phone: 2 } },
    });
  });

  it('creates and selects a list from the wizard without leaving or losing message settings', async () => {
    const wrapper = mount(CampaignWizard, {
      props: { metadata: { sanitized_lists: [] } },
      global: { mocks: { $t: key => key } },
    });
    await flushPromises();
    wrapper.vm.form.name = 'Pilot';
    wrapper.vm.form.steps[0].body = 'Keep my text';
    await wrapper
      .findAll('button')
      .find(button =>
        button.text().includes('JRC_CAMPAIGNS.WIZARD.SOURCE_MANUAL')
      )
      .trigger('click');
    const input = wrapper.getComponent(CampaignAudienceInput);
    await input.get('textarea').setValue('5511999990001');
    await input.get('button').trigger('click');
    await flushPromises();
    expect(wrapper.vm.form.audience_type).toBe('sanitized_list');
    expect(wrapper.vm.form.audience_config.sanitized_list_id).toBe(42);
    expect(wrapper.vm.form.steps[0].body).toBe('Keep my text');
    expect(wrapper.vm.audienceInputMode).toBeNull();
    expect(wrapper.emitted('refreshSenders')).toHaveLength(1);
  });

  it('does not replace the selected list preview with an older pending request', async () => {
    let resolveOld;
    api.audiencePreview.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolveOld = resolve;
        })
    );
    const wrapper = mount(CampaignWizard, {
      props: { metadata: { sanitized_lists: [] } },
      global: { mocks: { $t: key => key } },
    });
    await flushPromises();
    await wrapper.vm.selectCreatedList({ id: 42, name: 'Pilot' });
    expect(wrapper.vm.audiencePreview.estimated_recipients).toBe(2);
    resolveOld({ data: { estimated_recipients: 99, sample: [] } });
    await flushPromises();
    expect(wrapper.vm.audiencePreview.estimated_recipients).toBe(2);
  });

  it('does not present the Meta message-window instruction for a QR sender', async () => {
    const wrapper = mount(CampaignWizard, {
      props: {
        metadata: {
          whatsapp_inboxes: [
            {
              id: 8,
              name: 'QR',
              connector: 'broker',
              health_status: 'CONNECTED',
            },
          ],
        },
      },
      global: { mocks: { $t: key => key } },
    });
    wrapper.vm.stepIndex = 2;
    await flushPromises();
    expect(wrapper.text()).not.toContain('JRC_CAMPAIGNS.WIZARD.COMPLIANCE');
  });

  it('adds manually entered numbers to a list without granting consent or launching', async () => {
    const wrapper = mount(CampaignAudienceInput, {
      props: { mode: 'manual', campaignName: 'Pilot' },
    });
    await wrapper.get('textarea').setValue('5511999990001\n5511999990002');
    await wrapper.get('button').trigger('click');
    await flushPromises();
    expect(api.createSanitizedList).toHaveBeenCalledExactlyOnceWith({
      name: 'Pilot',
      entries: [{ phone: '5511999990001' }, { phone: '5511999990002' }],
    });
    expect(wrapper.emitted('selected')).toEqual([
      [{ id: 42, name: 'Pilot', stats: { valid_phone: 2 } }],
    ]);
  });

  it('reads quoted CSV and selects only the list returned by the server', async () => {
    const wrapper = mount(CampaignAudienceInput, {
      props: { mode: 'csv', campaignName: 'Pilot' },
    });
    const input = wrapper.get('input[type="file"]');
    Object.defineProperty(input.element, 'files', {
      value: [
        { text: async () => 'nome;telefone\n"Test; Person";5511999990001' },
      ],
    });
    await input.trigger('change');
    await flushPromises();
    expect(api.createSanitizedList).not.toHaveBeenCalled();
    await wrapper.get('button').trigger('click');
    await flushPromises();
    expect(api.createSanitizedList).toHaveBeenCalledWith({
      name: 'Pilot',
      entries: [{ name: 'Test; Person', phone: '5511999990001', email: '' }],
    });
    expect(wrapper.emitted('selected')[0][0].id).toBe(42);
  });

  it('retains the entered numbers when the server rejects the list', async () => {
    api.createSanitizedList.mockRejectedValueOnce({
      response: { data: { errors: ['Import failed'] } },
    });
    const wrapper = mount(CampaignAudienceInput, {
      props: { mode: 'manual', campaignName: 'Pilot' },
    });
    await wrapper.get('textarea').setValue('5511999990001');
    await wrapper.get('button').trigger('click');
    await flushPromises();
    expect(wrapper.get('[role="alert"]').text()).toBe('Import failed');
    expect(wrapper.get('textarea').element.value).toBe('5511999990001');
    expect(wrapper.emitted('selected')).toBeUndefined();
  });
});
