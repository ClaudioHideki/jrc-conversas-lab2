import { flushPromises, mount } from '@vue/test-utils';
import { computed } from 'vue';
import { createI18n } from 'vue-i18n';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import NewTicket from './NewTicket.vue';
import { request } from './client';
import en from './en.json';

vi.mock('./client', async importOriginal => ({
  ...(await importOriginal()),
  request: vi.fn(),
}));

const service = {
  id: '12',
  revision: 'published-revision',
  name: 'Customer support',
  unit: 'Support unit',
  category: 'Help',
  form_fields: [],
  contracts: [],
};
const buildWrapper = () =>
  mount(NewTicket, {
    global: {
      plugins: [createI18n({ legacy: false, locale: 'en', messages: { en } })],
      provide: {
        portalContext: computed(() => ({
          organization: 'Authorized organization',
          contact: {
            name: 'Master requester',
            email: 'master@example.test',
            phone_number: '+5511999990011',
          },
        })),
      },
      stubs: {
        RouterLink: { props: ['to'], template: '<a :href="to"><slot /></a>' },
      },
    },
  });

describe('Requester portal ticket opening', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    request.mockResolvedValue({ services: [service] });
  });

  it('reviews the authorized master contact and catalogue before creating a native ticket', async () => {
    const wrapper = buildWrapper();
    await flushPromises();
    expect(wrapper.text()).toContain('Master requester');
    expect(wrapper.text()).toContain('master@example.test');
    expect(wrapper.text()).toContain('+5511999990011');
    await wrapper.get('select').setValue(service.id);
    await wrapper.get('input[maxlength="255"]').setValue('Public request');
    await wrapper.get('textarea').setValue('Description for support');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(request).toHaveBeenCalledTimes(1);
    expect(wrapper.get('h1').text()).toBe(en.PORTAL.REVIEW_TITLE);
    request.mockResolvedValueOnce({
      ticket: {
        id: '42',
        number: '42',
        title: 'Public request',
        description: 'Description for support',
      },
    });
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    const [path, options] = request.mock.calls[1];
    expect(path).toBe('/portal/api/chamados');
    expect(options.method).toBe('POST');
    expect(options.headers['Idempotency-Key']).toBeTruthy();
    expect(JSON.parse(options.body.get('ticket'))).toEqual({
      service_id: '12',
      service_revision: 'published-revision',
      title: 'Public request',
      description: 'Description for support',
      service_fields: {},
    });
    expect(wrapper.get('a').attributes('href')).toBe('/chamados/42');
    expect(wrapper.get('h1').text()).toContain('42');
  });

  it('reuses an uncertain submission key when the requester retries confirmation', async () => {
    const wrapper = buildWrapper();
    await flushPromises();
    await wrapper.get('select').setValue(service.id);
    await wrapper.get('input[maxlength="255"]').setValue('Public request');
    await wrapper.get('textarea').setValue('Description for support');
    await wrapper.get('form').trigger('submit');
    request.mockRejectedValue(new Error('Connection interrupted'));
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    await wrapper.get('button[type="button"]').trigger('click');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(request.mock.calls[1][1].headers['Idempotency-Key']).toBe(
      request.mock.calls[2][1].headers['Idempotency-Key']
    );
    expect(wrapper.find('select[name="priority"]').exists()).toBe(false);
    expect(wrapper.find('input[type="email"]').exists()).toBe(false);
    expect(wrapper.find('input[type="tel"]').exists()).toBe(false);
  });

  it('blocks a changed request while its previous submission outcome remains uncertain', async () => {
    const wrapper = buildWrapper();
    await flushPromises();
    await wrapper.get('select').setValue(service.id);
    await wrapper.get('input[maxlength="255"]').setValue('Public request');
    await wrapper.get('textarea').setValue('Description for support');
    await wrapper.get('form').trigger('submit');
    request.mockRejectedValue(
      new Error('Connection interrupted after possible commit')
    );
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    await wrapper.get('button[type="button"]').trigger('click');
    await wrapper.get('input[maxlength="255"]').setValue('Changed request');
    await wrapper.get('form').trigger('submit');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(request).toHaveBeenCalledTimes(2);
    expect(wrapper.get('[role="alert"]').text()).toBe(
      en.PORTAL.SUBMISSION_UNCERTAIN
    );
  });
});
