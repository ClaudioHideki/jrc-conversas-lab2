import { describe, expect, it, vi } from 'vitest';
import { mount } from '@vue/test-utils';
import ConfigurationRevisionConflict from './ConfigurationRevisionConflict.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
const render = resource =>
  mount(ConfigurationRevisionConflict, {
    props: {
      state: {
        conflict: true,
        latest: { kind: resource === 'units' ? 'sac' : 'ddd', version: 1 },
      },
      resource,
      draft: { kind: resource === 'units' ? 'sac' : 'ddd', version: 1 },
    },
    global: { stubs: { Button: true } },
  });
describe('native revision comparison field meaning', () => {
  it('labels the native routing criterion without reusing the unit kind heading', () => {
    const wrapper = render('routing_rules');
    expect(wrapper.text()).toContain('JRC_CONTACT_CENTER.ROUTING_DRAFTS.KIND');
    expect(wrapper.text()).not.toContain('JRC_CONTACT_CENTER.ADMIN.KIND');
    wrapper.unmount();
  });
  it('preserves unit headings in the unchanged native unit comparison', () => {
    const wrapper = render('units');
    expect(wrapper.text()).toContain('JRC_CONTACT_CENTER.ADMIN.KIND');
    expect(wrapper.text()).not.toContain(
      'JRC_CONTACT_CENTER.ROUTING_DRAFTS.KIND'
    );
    wrapper.unmount();
  });
});
