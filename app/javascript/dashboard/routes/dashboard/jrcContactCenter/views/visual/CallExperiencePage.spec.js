import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { reactive } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import CallExperiencePage from './CallExperiencePage.vue';

const mocks = vi.hoisted(() => ({ route: null }));
vi.mock('vue-router', () => ({ useRoute: () => mocks.route }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { context: vi.fn() },
}));
const render = () =>
  mount(CallExperiencePage, {
    global: {
      stubs: {
        VisualShowcasePage: {
          template: '<p data-reference>REFERENCE ONLY</p>',
        },
        CallWorkspace: {
          props: ['callId'],
          template: '<p data-native-call>{{ callId }}</p>',
        },
      },
    },
  });
enableAutoUnmount(afterEach);
beforeEach(() => {
  vi.clearAllMocks();
  mocks.route = reactive({ params: { accountId: '1' }, query: {} });
  API.context.mockResolvedValue({ data: { capabilities: { operate: true } } });
});

describe('native call versus visual reference', () => {
  it('preserves the identified visual reference when no operational call is selected', async () => {
    const wrapper = render();
    await flushPromises();
    expect(wrapper.find('[data-reference]').exists()).toBe(true);
    expect(wrapper.find('[data-native-call]').exists()).toBe(false);
  });
  it('shows only the native workspace for an explicit operational call', async () => {
    mocks.route.params.callId = '7';
    const wrapper = render();
    await flushPromises();
    expect(wrapper.get('[data-native-call]').text()).toBe('7');
    expect(wrapper.find('[data-reference]').exists()).toBe(false);
  });
  it('does not substitute a demonstration for a selected call when its context lookup fails', async () => {
    mocks.route.query.callId = '8';
    API.context.mockRejectedValueOnce(
      new Error('SYNTHETIC unavailable context')
    );
    const wrapper = render();
    await flushPromises();
    expect(wrapper.get('[data-native-call]').text()).toBe('8');
    expect(wrapper.find('[data-reference]').exists()).toBe(false);
  });
});
