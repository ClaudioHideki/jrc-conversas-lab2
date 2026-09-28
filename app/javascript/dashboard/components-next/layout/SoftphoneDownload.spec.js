import { mount } from '@vue/test-utils';
import { afterEach, describe, expect, it } from 'vitest';
import SoftphoneDownload from './SoftphoneDownload.vue';

describe('Softphone download in the Web header', () => {
  afterEach(() => {
    delete window.chatwootConfig;
    delete window.jrcSoftphoneDesktop;
  });

  it.each([
    undefined,
    '',
    'C:\\JRC\\Setup.exe',
    'file:///Setup.exe',
    'http://downloads.example/setup.exe',
    // eslint-disable-next-line no-script-url
    'javascript:alert(1)',
    'https://user:password@example.com/setup.exe',
  ])('hides download for absent/unsafe URL %s', value => {
    window.chatwootConfig = { softphoneDownloadUrl: value };
    const wrapper = mount(SoftphoneDownload);
    expect(wrapper.find('a').exists()).toBe(false);
    wrapper.unmount();
  });

  it('uses the configured public HTTPS URL without inventing a download location', () => {
    window.chatwootConfig = {
      softphoneDownloadUrl: 'https://downloads.example/JRC-Softphone-Setup.exe',
    };
    const wrapper = mount(SoftphoneDownload);
    const link = wrapper.get('a');
    expect(link.attributes('href')).toBe(
      window.chatwootConfig.softphoneDownloadUrl
    );
    expect(link.attributes('rel')).toBe('noopener noreferrer');
    expect(link.text()).toBe('Download JRC Softphone');
    wrapper.unmount();
  });

  it('does not offer an installer inside the already installed Desktop', () => {
    window.chatwootConfig = {
      softphoneDownloadUrl: 'https://downloads.example/Setup.exe',
    };
    window.jrcSoftphoneDesktop = {};
    const wrapper = mount(SoftphoneDownload);
    expect(wrapper.find('a').exists()).toBe(false);
    wrapper.unmount();
  });
});
