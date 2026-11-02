import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { flushPromises, shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import { API, removeHeader, setHeader } from 'widget/helpers/axios';
import en from 'widget/i18n/locale/en.json';
import ptBR from 'widget/i18n/locale/pt_BR.json';
import AgentMessage from '../AgentMessage.vue';
import UserMessage from '../UserMessage.vue';
import ImageBubble from '../ImageBubble.vue';
import VideoBubble from '../VideoBubble.vue';
import FileBubble from '../FileBubble.vue';
import ProtectedAttachmentStatus from '../ProtectedAttachmentStatus.vue';

const NativeURL = URL;
const message = attachment => ({
  id: 12,
  content: 'Public conversation message',
  content_type: 'text',
  content_attributes: {},
  created_at: 1700000000,
  sender: { name: 'Agent' },
  attachments: [attachment],
});
let wrapper;
let revokeObjectURL;
const render = (component, attachment, locale = 'en') => {
  wrapper = shallowMount(component, {
    props: { message: message(attachment) },
    global: {
      plugins: [
        createI18n({ legacy: false, locale, messages: { en, pt_BR: ptBR } }),
        createStore({
          modules: {
            appConfig: {
              namespaced: true,
              getters: { getWidgetColor: () => '#1f93ff' },
            },
          },
        }),
      ],
      directives: { 'dompurify-html': () => {} },
      stubs: {
        DragWrapper: { template: '<div><slot /></div>' },
        ProtectedAttachmentStatus: false,
      },
    },
  });
};

beforeEach(() => {
  class TestURL extends NativeURL {}
  TestURL.createObjectURL = vi.fn().mockReturnValue('blob:protected-evidence');
  revokeObjectURL = vi.fn();
  TestURL.revokeObjectURL = revokeObjectURL;
  vi.stubGlobal('URL', TestURL);
  window.chatwootWebChannel = {
    websiteToken: 'widget-token',
    enabledFeatures: [],
  };
  setHeader('native-visitor');
  vi.spyOn(API, 'get').mockResolvedValue({
    data: new Blob(['evidence'], { type: 'image/png' }),
  });
});

afterEach(() => {
  wrapper?.unmount();
  wrapper = null;
  removeHeader('X-Auth-Token');
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

describe.each([
  { name: 'AgentMessage', component: AgentMessage },
  { name: 'UserMessage', component: UserMessage },
])('$name attachment rendering', ({ component }) => {
  it.each([
    { fileType: 'image', bubble: ImageBubble },
    { fileType: 'video', bubble: VideoBubble },
    { fileType: 'file', bubble: FileBubble },
  ])(
    'passes an ObjectURL to its $fileType bubble for a protected SD attachment',
    async ({ fileType, bubble }) => {
      render(component, {
        id: 34,
        file_type: fileType,
        filename: 'Evidence 100%.png',
        data_url: 'https://foreign.example/do-not-authenticate',
        service_desk_protected: true,
      });
      expect(wrapper.findComponent(bubble).exists()).toBe(false);
      expect(wrapper.getComponent(ProtectedAttachmentStatus).text()).toContain(
        'Loading attachment...'
      );
      expect(wrapper.text()).toContain('Evidence 100%.png');
      await flushPromises();
      expect(wrapper.findComponent(bubble).props('url')).toBe(
        'blob:protected-evidence'
      );
      if (fileType === 'image') {
        expect(wrapper.findComponent(bubble).props('thumb')).toBe(
          'blob:protected-evidence'
        );
      }
      if (fileType === 'file') {
        expect(wrapper.findComponent(bubble).props('filename')).toBe(
          'Evidence 100%.png'
        );
      }
      expect(API.get.mock.calls[0][0]).toBe(
        '/api/v1/widget/messages/12/attachments/34'
      );
    }
  );

  it('preserves ordinary native image URLs without authenticated download requests', () => {
    render(component, {
      id: 34,
      file_type: 'image',
      data_url: 'https://cdn.example/original.png',
    });
    expect(wrapper.findComponent(ImageBubble).props('url')).toBe(
      'https://cdn.example/original.png'
    );
    expect(wrapper.findComponent(ImageBubble).props('thumb')).toBe(
      'https://cdn.example/original.png'
    );
    expect(API.get).not.toHaveBeenCalled();
  });

  it('drops the prior protected URL when reused for another message', async () => {
    render(component, {
      id: 34,
      file_type: 'image',
      service_desk_protected: true,
    });
    await flushPromises();
    await wrapper.setProps({
      message: {
        ...message({ id: 99, file_type: 'image', data_url: '/new-native.png' }),
        id: 56,
      },
    });
    expect(revokeObjectURL).toHaveBeenCalledWith('blob:protected-evidence');
    expect(wrapper.findComponent(ImageBubble).props('url')).toBe(
      '/new-native.png'
    );
  });

  it('keeps a scan-pending attachment visible and retries safely after an explicit click', async () => {
    API.get.mockRejectedValueOnce({
      response: { status: 409, data: { code: 'attachment_scan_unavailable' } },
    });
    render(component, {
      id: 34,
      file_type: 'file',
      filename: 'Pending evidence.pdf',
      service_desk_protected: true,
      data_url: 'https://foreign.example/must-not-be-used',
    });
    await flushPromises();
    const status = wrapper.getComponent(ProtectedAttachmentStatus);
    expect(status.text()).toContain('Pending evidence.pdf');
    expect(status.text()).toContain('Waiting for file verification');
    expect(wrapper.findComponent(FileBubble).exists()).toBe(false);
    expect(wrapper.find('a').exists()).toBe(false);
    await flushPromises();
    expect(API.get).toHaveBeenCalledOnce();
    await status.get('button').trigger('click');
    await flushPromises();
    expect(API.get).toHaveBeenCalledTimes(2);
    expect(API.get.mock.calls[1][0]).toBe(
      '/api/v1/widget/messages/12/attachments/34'
    );
    expect(wrapper.findComponent(ProtectedAttachmentStatus).exists()).toBe(
      false
    );
    expect(wrapper.getComponent(FileBubble).props('url')).toBe(
      'blob:protected-evidence'
    );
  });

  it('keeps a denied attachment visible as unavailable without a retry or direct URL', async () => {
    API.get.mockRejectedValueOnce({ response: { status: 404 } });
    render(component, {
      id: 34,
      file_type: 'image',
      filename: 'Unavailable evidence.png',
      service_desk_protected: true,
      data_url: 'https://foreign.example/must-not-be-used',
    });
    await flushPromises();
    const status = wrapper.getComponent(ProtectedAttachmentStatus);
    expect(status.text()).toContain('Unavailable evidence.png');
    expect(status.text()).toContain('Attachment unavailable');
    expect(status.find('button').exists()).toBe(false);
    expect(wrapper.findComponent(ImageBubble).exists()).toBe(false);
    expect(wrapper.find('a').exists()).toBe(false);
    expect(API.get).toHaveBeenCalledOnce();
  });

  it('offers explicit retry for a temporary error and uses PT-BR labels', async () => {
    API.get.mockRejectedValueOnce({ response: { status: 503 } });
    render(
      component,
      {
        id: 34,
        file_type: 'file',
        filename: 'Evidência.pdf',
        service_desk_protected: true,
      },
      'pt_BR'
    );
    expect(wrapper.text()).toContain('Carregando anexo...');
    await flushPromises();
    const status = wrapper.getComponent(ProtectedAttachmentStatus);
    expect(status.text()).toContain(
      'Não foi possível carregar o anexo. Tente novamente.'
    );
    expect(status.get('button').text()).toBe('Tentar novamente');
    await status.get('button').trigger('click');
    await flushPromises();
    expect(API.get).toHaveBeenCalledTimes(2);
    expect(wrapper.getComponent(FileBubble).props('url')).toBe(
      'blob:protected-evidence'
    );
  });
});

it('uses the protected ObjectURL for an agent audio source', async () => {
  render(AgentMessage, {
    id: 34,
    file_type: 'audio',
    service_desk_protected: true,
    data_url: 'https://foreign.example/audio',
  });
  await flushPromises();
  expect(wrapper.get('audio source').attributes('src')).toBe(
    'blob:protected-evidence'
  );
});

it('shows a protected filename without interpreting percent escapes in it', () => {
  wrapper = shallowMount(FileBubble, {
    props: { url: 'blob:protected-evidence', filename: 'Evidence 100%.pdf' },
    global: { mocks: { $t: key => key } },
  });
  expect(wrapper.text()).toContain('Evidence 100%.pdf');
  expect(wrapper.get('a.download').attributes('download')).toBe(
    'Evidence 100%.pdf'
  );
});
