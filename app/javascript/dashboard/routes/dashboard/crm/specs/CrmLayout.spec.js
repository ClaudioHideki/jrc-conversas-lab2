import { mount, flushPromises } from '@vue/test-utils';
import { reactive } from 'vue';
import CrmLayout from '../CrmLayout.vue';

const mocks = vi.hoisted(() => ({ route: null, resize: null }));
vi.mock('vue-router', () => ({ useRoute: () => mocks.route }));
vi.mock('vuex', () => ({
  useStore: () => ({ getters: { getCurrentRole: 'administrator' } }),
}));
vi.mock('@vueuse/core', () => ({
  useResizeObserver: (_element, callback) => {
    mocks.resize = callback;
  },
}));

describe('CRM module navigation', () => {
  let wrapper;
  let scroll;
  beforeEach(() => {
    mocks.route = reactive({
      name: 'crm_dashboard',
      params: { accountId: '1' },
    });
    scroll = vi.fn();
    Element.prototype.scrollBy = scroll;
    vi.spyOn(Element.prototype, 'getBoundingClientRect').mockImplementation(
      function bounds() {
        return this.getAttribute('aria-current') === 'page'
          ? { left: 900, right: 1050 }
          : { left: 0, right: 600 };
      }
    );
    wrapper = mount(CrmLayout, {
      global: {
        stubs: {
          RouterLink: {
            props: ['to'],
            template: '<a :href="to.name"><slot /></a>',
          },
          RouterView: true,
        },
      },
    });
  });
  afterEach(() => {
    wrapper.unmount();
    delete Element.prototype.scrollBy;
    vi.restoreAllMocks();
  });

  it('reveals the active tab on entry, route changes and resize', async () => {
    await flushPromises();
    expect(scroll).toHaveBeenCalledWith({ left: 450 });
    expect(wrapper.get('[aria-current="page"]').attributes('href')).toBe(
      'crm_dashboard'
    );
    mocks.route.name = 'crm_settings';
    await flushPromises();
    expect(wrapper.get('[aria-current="page"]').attributes('href')).toBe(
      'crm_settings'
    );
    expect(scroll.mock.instances.at(-1)).toBe(wrapper.get('nav > div').element);
    const before = scroll.mock.calls.length;
    await mocks.resize();
    expect(scroll.mock.calls.length).toBe(before + 1);
    expect(scroll.mock.calls.every(([options]) => !('top' in options))).toBe(
      true
    );
  });

  it('provides overflow controls and updates them after horizontal scrolling', async () => {
    const list = wrapper.get('nav > div').element;
    Object.defineProperties(list, {
      clientWidth: { configurable: true, value: 600 },
      scrollWidth: { configurable: true, value: 1800 },
      scrollLeft: { configurable: true, writable: true, value: 0 },
    });
    await mocks.resize();
    const buttons = wrapper.findAll('nav button');
    expect(buttons[0].element.disabled).toBe(true);
    expect(buttons[1].element.disabled).toBe(false);
    await buttons[1].trigger('click');
    expect(list.scrollBy).toHaveBeenCalledWith({ left: 450 });
    list.scrollLeft = 1200;
    await wrapper.get('nav > div').trigger('scroll');
    expect(buttons[0].element.disabled).toBe(false);
    expect(buttons[1].element.disabled).toBe(true);
  });
});
