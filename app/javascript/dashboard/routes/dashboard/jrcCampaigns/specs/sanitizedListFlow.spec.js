import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import SanitizedLists from '../components/SanitizedLists.vue';
import api from 'dashboard/api/jrcCampaigns';
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/jrcCampaigns', () => ({
  default: { createSanitizedList: vi.fn() },
}));
enableAutoUnmount(afterEach);

describe('sanitized list to campaign workflow', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    api.createSanitizedList.mockResolvedValue({
      data: {
        id: 7,
        name: 'QA',
        stats: { total: 1, valid: 1 },
        entries: [
          {
            id: 8,
            name: 'QA, Contact',
            phone_number: '+5511999999000',
            status: 'valid',
          },
        ],
      },
    });
  });
  it('keeps quoted CSV intact, displays server results and passes the actual list into the campaign without sending', async () => {
    const wrapper = mount(SanitizedLists);
    await wrapper.get('input:not([type="file"])').setValue('QA');
    await wrapper
      .get('textarea')
      .setValue('nome,telefone\n"QA, Contact",+5511999999000');
    await wrapper.get('button').trigger('click');
    await flushPromises();
    expect(api.createSanitizedList).toHaveBeenCalledExactlyOnceWith({
      name: 'QA',
      entries: [{ name: 'QA, Contact', phone: '+5511999999000', email: '' }],
    });
    expect(wrapper.emitted('changed')).toEqual([[]]);
    expect(wrapper.get('tbody').text()).toContain('+5511999999000');
    const useList = wrapper
      .findAll('button')
      .find(button => button.text() === 'JRC_CAMPAIGNS.SANITIZE.USE_LIST');
    await useList.trigger('click');
    expect(wrapper.emitted('useList')).toEqual([
      [expect.objectContaining({ id: 7 })],
    ]);
    expect(api.createSanitizedList).toHaveBeenCalledOnce();
  });
  it('explains malformed CSV and blocks submission before any API request', async () => {
    const wrapper = mount(SanitizedLists);
    await wrapper.get('input:not([type="file"])').setValue('QA');
    await wrapper
      .get('textarea')
      .setValue('name,phone\n"Unclosed,+5511999999000');
    expect(wrapper.get('[role="alert"]').text()).toBe(
      'JRC_CAMPAIGNS.SANITIZE.PARSE_ERROR'
    );
    expect(wrapper.get('button').element.disabled).toBe(true);
    await wrapper.vm.sanitize();
    expect(api.createSanitizedList).not.toHaveBeenCalled();
  });
  it('preserves the input and displays API errors without claiming success', async () => {
    api.createSanitizedList.mockRejectedValueOnce({
      response: { data: { errors: ['Synthetic failure'] } },
    });
    const wrapper = mount(SanitizedLists);
    await wrapper.get('input:not([type="file"])').setValue('QA');
    await wrapper.get('textarea').setValue('+5511999999000');
    await wrapper.vm.sanitize();
    await flushPromises();
    expect(wrapper.get('[role="alert"]').text()).toBe('Synthetic failure');
    expect(wrapper.get('textarea').element.value).toBe('+5511999999000');
    expect(wrapper.emitted('changed')).toBeUndefined();
    expect(wrapper.emitted('useList')).toBeUndefined();
  });
});
