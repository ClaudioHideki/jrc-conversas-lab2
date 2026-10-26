import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { computed, defineComponent } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { API, removeHeader, setHeader } from 'widget/helpers/axios';
import { useMessageAttachments } from '../useMessageAttachments';

const NativeURL = URL;
const Host = defineComponent({
  props: { message: { type: Object, required: true } },
  setup(props) {
    return useMessageAttachments(computed(() => props.message));
  },
  template: `<div v-for="file in resolvedAttachments" :key="file.id">
      <a v-if="!file.downloadState || file.downloadState === 'ready'" :href="file.data_url">attachment</a>
      <span v-else :data-state="file.downloadState">{{ file.filename }}</span>
    </div>`,
});
const protectedMessage = (id = 12) => ({
  id,
  attachments: [
    {
      id: 34,
      filename: 'Evidence.pdf',
      service_desk_protected: true,
      data_url: 'https://untrusted.example/never-request-this',
    },
  ],
});
let wrapper;
let createObjectURL;
let revokeObjectURL;

beforeEach(() => {
  createObjectURL = vi.fn().mockReturnValue('blob:widget-evidence');
  revokeObjectURL = vi.fn();
  class TestURL extends NativeURL {}
  TestURL.createObjectURL = createObjectURL;
  TestURL.revokeObjectURL = revokeObjectURL;
  vi.stubGlobal('URL', TestURL);
  window.chatwootWebChannel = { websiteToken: 'widget-token' };
  setHeader('first-native-visitor');
  vi.spyOn(API, 'get').mockResolvedValue({
    data: new Blob(['picture'], { type: 'image/png' }),
  });
});

afterEach(() => {
  wrapper?.unmount();
  wrapper = null;
  removeHeader('X-Auth-Token');
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

describe('protected native widget attachment URLs', () => {
  it('keeps ordinary attachments unchanged and never forwards their external URLs to axios', () => {
    const ordinary = {
      id: 1,
      attachments: [
        { id: 2, data_url: 'https://cdn.example/native-file.pdf' },
        {
          id: 3,
          service_desk_protected: 'true',
          data_url: 'https://cdn.example/external-picture.png',
        },
      ],
    };
    wrapper = mount(Host, { props: { message: ordinary } });
    expect(wrapper.findAll('a').map(link => link.attributes('href'))).toEqual([
      'https://cdn.example/native-file.pdf',
      'https://cdn.example/external-picture.png',
    ]);
    expect(API.get).not.toHaveBeenCalled();
    expect(createObjectURL).not.toHaveBeenCalled();
  });

  it('renders only a downloaded ObjectURL for an SD attachment and revokes it on unmount', async () => {
    wrapper = mount(Host, { props: { message: protectedMessage() } });
    expect(wrapper.find('a').exists()).toBe(false);
    expect(wrapper.get('[data-state]').attributes('data-state')).toBe(
      'loading'
    );
    expect(wrapper.text()).toContain('Evidence.pdf');
    await flushPromises();
    expect(wrapper.get('a').attributes('href')).toBe('blob:widget-evidence');
    expect(API.get.mock.calls[0][0]).toBe(
      '/api/v1/widget/messages/12/attachments/34'
    );
    expect(createObjectURL.mock.calls[0][0].type).toBe('image/png');
    wrapper.unmount();
    wrapper = null;
    expect(revokeObjectURL).toHaveBeenCalledExactlyOnceWith(
      'blob:widget-evidence'
    );
  });

  it('revokes cached URLs and aborts a request immediately when the native JWT changes', async () => {
    wrapper = mount(Host, { props: { message: protectedMessage() } });
    await flushPromises();
    const oldSignal = API.get.mock.calls[0][1].signal;
    API.get.mockReturnValueOnce(new Promise(() => {}));
    setHeader('second-native-visitor');
    expect(oldSignal.aborted).toBe(true);
    expect(revokeObjectURL).toHaveBeenCalledWith('blob:widget-evidence');
    await flushPromises();
    expect(wrapper.find('a').exists()).toBe(false);
    expect(API.get).toHaveBeenCalledTimes(2);
    removeHeader('X-Auth-Token');
    expect(API.get.mock.calls[1][1].signal.aborted).toBe(true);
    expect(API.get).toHaveBeenCalledTimes(2);
  });

  it('revokes URLs on message replacement and ignores an old response after identity replacement', async () => {
    let complete;
    API.get.mockReturnValueOnce(
      new Promise(resolve => {
        complete = resolve;
      })
    );
    wrapper = mount(Host, { props: { message: protectedMessage() } });
    setHeader('second-native-visitor');
    await flushPromises();
    expect(createObjectURL).toHaveBeenCalledOnce();
    complete({ data: new Blob(['old identity'], { type: 'image/png' }) });
    await flushPromises();
    expect(createObjectURL).toHaveBeenCalledOnce();
    await wrapper.setProps({ message: { id: 99, attachments: [] } });
    expect(revokeObjectURL).toHaveBeenCalledWith('blob:widget-evidence');
    expect(wrapper.find('a').exists()).toBe(false);
  });

  it('ignores a request that completes after unmount without creating an ObjectURL', async () => {
    let complete;
    API.get.mockReturnValueOnce(
      new Promise(resolve => {
        complete = resolve;
      })
    );
    wrapper = mount(Host, { props: { message: protectedMessage() } });
    wrapper.unmount();
    wrapper = null;
    expect(API.get.mock.calls[0][1].signal.aborted).toBe(true);
    complete({ data: new Blob(['old bytes'], { type: 'image/png' }) });
    await flushPromises();
    expect(createObjectURL).not.toHaveBeenCalled();
  });

  it('keeps the filename unavailable without a URL fallback or retry after access is denied', async () => {
    API.get.mockRejectedValueOnce({ response: { status: 404 } });
    wrapper = mount(Host, { props: { message: protectedMessage() } });
    await flushPromises();
    expect(wrapper.find('a').exists()).toBe(false);
    expect(wrapper.get('[data-state]').attributes('data-state')).toBe(
      'unavailable'
    );
    expect(wrapper.text()).toContain('Evidence.pdf');
    wrapper.vm.retryAttachment(34);
    expect(createObjectURL).not.toHaveBeenCalled();
    expect(API.get).toHaveBeenCalledOnce();
  });

  it('decodes the scan-conflict Blob envelope and retries only when requested', async () => {
    API.get.mockRejectedValueOnce({
      response: {
        status: 409,
        data: {
          text: vi
            .fn()
            .mockResolvedValue(
              JSON.stringify({ code: 'attachment_scan_unavailable' })
            ),
        },
      },
    });
    wrapper = mount(Host, { props: { message: protectedMessage() } });
    await flushPromises();
    expect(wrapper.get('[data-state]').attributes('data-state')).toBe(
      'scan_pending'
    );
    expect(wrapper.text()).toContain('Evidence.pdf');
    expect(wrapper.find('a').exists()).toBe(false);
    await flushPromises();
    expect(API.get).toHaveBeenCalledOnce();
    wrapper.vm.retryAttachment(34);
    expect(API.get).toHaveBeenCalledTimes(2);
    await flushPromises();
    expect(wrapper.get('a').attributes('href')).toBe('blob:widget-evidence');
    wrapper.vm.retryAttachment(34);
    expect(API.get).toHaveBeenCalledTimes(2);
  });

  it.each([undefined, 408, 429, 503])(
    'allows an explicit retry after a temporary failure %s',
    async status => {
      API.get.mockRejectedValueOnce({ response: status ? { status } : null });
      wrapper = mount(Host, { props: { message: protectedMessage() } });
      await flushPromises();
      expect(wrapper.get('[data-state]').attributes('data-state')).toBe(
        'temporary_error'
      );
      expect(API.get).toHaveBeenCalledOnce();
      wrapper.vm.retryAttachment(34);
      await flushPromises();
      expect(wrapper.get('a').attributes('href')).toBe('blob:widget-evidence');
      expect(API.get).toHaveBeenCalledTimes(2);
    }
  );

  it('does not let an old error-body decode replace a new visitor download state', async () => {
    let complete;
    API.get.mockRejectedValueOnce({
      response: {
        status: 409,
        data: {
          text: () =>
            new Promise(resolve => {
              complete = resolve;
            }),
        },
      },
    });
    wrapper = mount(Host, { props: { message: protectedMessage() } });
    await flushPromises();
    setHeader('second-native-visitor');
    await flushPromises();
    complete(JSON.stringify({ code: 'attachment_scan_unavailable' }));
    await flushPromises();
    expect(wrapper.get('a').attributes('href')).toBe('blob:widget-evidence');
    expect(wrapper.find('[data-state]').exists()).toBe(false);
  });

  it.each(['text/html', 'image/svg+xml', 'application/xhtml+xml'])(
    'keeps downloaded %s inert when opened as an ObjectURL',
    async type => {
      API.get.mockResolvedValueOnce({ data: new Blob(['active'], { type }) });
      wrapper = mount(Host, { props: { message: protectedMessage() } });
      await flushPromises();
      expect(createObjectURL.mock.calls[0][0].type).toBe(
        'application/octet-stream'
      );
    }
  );
});
