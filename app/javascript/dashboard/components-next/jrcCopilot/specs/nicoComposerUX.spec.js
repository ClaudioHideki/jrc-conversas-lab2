import { ref } from 'vue';
import { mount } from '@vue/test-utils';
import NicoComposer from '../NicoComposer.vue';

describe('NICO chat voice controls', () => {
  let wrapper;
  let voice;
  beforeEach(() => {
    voice = {
      supported: true,
      continuousSupported: true,
      continuousActive: ref(false),
      continuousCanStart: ref(true),
      requesting: ref(false),
      listening: ref(false),
      transcribing: ref(false),
      reviewing: ref(false),
      speaking: ref(false),
      speakingEnabled: ref(false),
      error: ref(''),
      start: vi.fn(),
      stop: vi.fn(),
      cancelReview: vi.fn(),
      stopSpeaking: vi.fn(),
      startConversation: vi.fn(),
      stopConversation: vi.fn(),
      setSpeakingEnabled: vi.fn(),
    };
    wrapper = mount(NicoComposer, { props: { voice } });
  });
  afterEach(() => wrapper.unmount());

  it('requires a click to start voice and separates conversation from dictation', async () => {
    expect(voice.startConversation).not.toHaveBeenCalled();
    expect(voice.start).not.toHaveBeenCalled();
    await wrapper.get('[aria-label="Conversar com o NICO"]').trigger('click');
    expect(voice.startConversation).toHaveBeenCalledOnce();
    expect(voice.start).not.toHaveBeenCalled();
    voice.continuousActive.value = true;
    await wrapper.vm.$nextTick();
    await wrapper
      .get('[aria-label="Encerrar conversa por voz"]')
      .trigger('click');
    expect(voice.stopConversation).toHaveBeenCalledOnce();
  });

  it('keeps explicit stop controls visible while NICO is speaking', async () => {
    voice.speaking.value = true;
    await wrapper.vm.$nextTick();
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'Interromper leitura')
      .trigger('click');
    expect(voice.stopSpeaking).toHaveBeenCalledOnce();
    await wrapper.get('[aria-label="Ouvir respostas"]').trigger('click');
    expect(voice.setSpeakingEnabled).toHaveBeenCalledWith(true);
  });

  it('does not allow microphone activation during a call but preserves text input', async () => {
    await wrapper.setProps({ inCall: true });
    voice.continuousCanStart.value = false;
    await wrapper.vm.$nextTick();
    expect(
      wrapper.get('[aria-label="Ditar mensagem"]').attributes('disabled')
    ).toBeDefined();
    expect(
      wrapper.get('[aria-label="Conversar com o NICO"]').attributes('disabled')
    ).toBeDefined();
    await wrapper.get('textarea').setValue('Continuar por texto');
    expect(wrapper.emitted('update:modelValue')[0]).toEqual([
      'Continuar por texto',
    ]);
    expect(voice.start).not.toHaveBeenCalled();
  });
});
