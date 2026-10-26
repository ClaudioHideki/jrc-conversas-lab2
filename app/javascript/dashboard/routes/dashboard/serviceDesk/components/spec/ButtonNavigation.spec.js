import { afterEach, describe, expect, it, vi } from 'vitest';
import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import NativeIncidentForm from '../NativeIncidentForm.vue';
const mocks = vi.hoisted(() => ({ createIncident: vi.fn() }));
vi.mock('dashboard/api/serviceDeskOperationsV2', () => ({ default: mocks }));
vi.mock('../../composables/useServiceDesk', () => ({
  useServiceDesk: () => ({
    state: {
      status: 'ready',
      context: {
        account_id: '1',
        units: [{ id: '2' }],
        capabilities: { incidents: { index: true } },
      },
    },
  }),
}));
let wrapper;
afterEach(() => {
  wrapper?.unmount();
  vi.clearAllMocks();
});
describe('secondary actions with real native button behavior', () => {
  it('canceling an otherwise valid incident form does not also submit it', async () => {
    wrapper = mount(NativeIncidentForm, {
      attachTo: document.body,
      props: { unitId: '2', kind: 'incident' },
      global: {
        plugins: [
          createI18n({
            legacy: false,
            locale: 'en',
            missingWarn: false,
            fallbackWarn: false,
          }),
        ],
        stubs: { Lookup: true },
      },
    });
    await wrapper.get('input[required]').setValue('Synthetic incident');
    const cancel = wrapper
      .findAll('button')
      .find(button => button.text().includes('COMMON.cancel'));
    await cancel.trigger('click');
    await flushPromises();
    expect(wrapper.emitted('cancel')).toHaveLength(1);
    expect(mocks.createIncident).not.toHaveBeenCalled();
    expect(wrapper.get('input[required]').element.value).toBe(
      'Synthetic incident'
    );
  });
});
