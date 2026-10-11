import { config, mount } from '@vue/test-utils';
import { reactive, ref } from 'vue';
import GlobalCallPanel from '../GlobalCallPanel.vue';

const state = vi.hoisted(() => ({ calls: null, initiating: null, nico: null }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/stores/calls', () => ({ useCallsStore: () => state.calls }));
vi.mock('dashboard/composables/useWhatsappCallSession', () => ({
  useWhatsappCallSession: () => ({ isInitiating: state.initiating }),
}));
vi.mock('dashboard/components-next/jrcCopilot/useJrcCopilot', () => ({
  useJrcCopilot: () => ({ isFull: state.nico }),
}));
vi.mock('dashboard/routes/dashboard/webphone/WebphonePage.vue', () => ({
  default: {
    name: 'WebphonePage',
    props: {
      compact: Boolean,
      externalBusy: Boolean,
      allowConference: Boolean,
    },
    template: '<div data-softphone />',
  },
}));
let wrapper;
let plugins;
beforeEach(() => {
  plugins = config.global.plugins;
  config.global.plugins = [];
  state.calls = reactive({ hasActiveCall: false, hasIncomingCall: false });
  state.initiating = ref(false);
  state.nico = ref(false);
});
afterEach(() => {
  wrapper?.unmount();
  config.global.plugins = plugins;
});
const render = props =>
  mount(GlobalCallPanel, {
    props: { allowSoftphone: true, ...props },
    global: { stubs: { teleport: true }, mocks: { $t: key => key } },
  });
it('opens only the existing compact softphone and preserves conference permission', () => {
  wrapper = render({ allowConference: true });
  expect(wrapper.findComponent({ name: 'WebphonePage' }).props()).toEqual({
    compact: true,
    externalBusy: false,
    allowConference: true,
  });
  expect(wrapper.find('.i-ri-whatsapp-fill').exists()).toBe(false);
});
it('does not mount a softphone when permission is absent', () => {
  wrapper = render({ allowSoftphone: false });
  expect(wrapper.findComponent({ name: 'WebphonePage' }).exists()).toBe(false);
});
it.each(['hasActiveCall', 'hasIncomingCall'])(
  'preserves the %s collision guard',
  field => {
    state.calls[field] = true;
    wrapper = render();
    expect(
      wrapper.findComponent({ name: 'WebphonePage' }).props('externalBusy')
    ).toBe(true);
  }
);
it('preserves the guard while another WhatsApp call is starting elsewhere', () => {
  state.initiating.value = true;
  wrapper = render();
  expect(
    wrapper.findComponent({ name: 'WebphonePage' }).props('externalBusy')
  ).toBe(true);
});
it('minimizes without ending or recreating a call', async () => {
  wrapper = render();
  await wrapper.get('button').trigger('click');
  expect(wrapper.emitted('close')).toHaveLength(1);
});
