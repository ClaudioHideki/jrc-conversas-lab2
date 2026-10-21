import { describe, expect, it, vi } from 'vitest';
import { config, mount } from '@vue/test-utils';
import {
  contactCenterVisualCatalog,
  contactCenterScreen,
} from '../../demo/contactCenterVisualCatalog';
import VisualShowcasePage from './VisualShowcasePage.vue';
import VisualProgress from './VisualProgress.vue';

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '1' } }),
}));

describe('localized visual experiences', () => {
  it('renders the full catalogs with their original content and demo notice', () => {
    const i18n = config.global.plugins[0];
    const catalogs = [[contactCenterVisualCatalog, contactCenterScreen]];
    catalogs.forEach(([catalog, screenFor]) => {
      Object.keys(catalog).forEach(key => {
        const screen = screenFor(key, i18n.global.t);
        const wrapper = mount(VisualShowcasePage, {
          props: { screen },
          global: {
            stubs: { RouterLink: { template: '<a><slot /></a>' } },
          },
        });
        expect(wrapper.get('h1').text()).toBe(catalog[key].title);
        expect(wrapper.text()).toContain('Demonstração');
        expect(wrapper.text()).not.toContain('JRC_CONTACT_CENTER.');
        wrapper.unmount();
      });
    });
  });

  it('preserves provider data and route identifiers when localizing', () => {
    const original = JSON.stringify(contactCenterVisualCatalog.customer360);
    const screen = contactCenterScreen(
      'customer360',
      key => `translated:${key}`
    );
    expect(screen.title).toMatch(/^translated:/);
    expect(screen.actions[0].routeName).toBe(
      contactCenterVisualCatalog.customer360.actions[0].routeName
    );
    expect(JSON.stringify(contactCenterVisualCatalog.customer360)).toBe(
      original
    );
  });

  it('preserves the visible percentage through i18n', () => {
    const wrapper = mount(VisualProgress, {
      props: { label: 'Progress', value: 75 },
    });
    expect(wrapper.get('strong').text()).toBe('75%');
    expect(wrapper.find('[class~="w-4/5"]').exists()).toBe(true);
  });
});
