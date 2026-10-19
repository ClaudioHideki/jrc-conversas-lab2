import { effectScope, ref } from 'vue';
import { useNicoVoiceConversation } from '../useNicoVoiceConversation';

describe('bounded operator voice conversation', () => {
  let scope;
  let voice;
  let recorders;
  let track;
  let approval;
  let inCall;
  let context;
  let visible;
  let canSubmit;
  let onSubmit;
  let amplitude;
  beforeEach(() => {
    vi.useFakeTimers();
    recorders = [];
    amplitude = 128;
    track = { stop: vi.fn() };
    class Recorder {
      static isTypeSupported() {
        return true;
      }

      constructor() {
        this.state = 'inactive';
        recorders.push(this);
      }

      start() {
        this.state = 'recording';
      }

      stop() {
        if (this.state !== 'recording') return;
        this.state = 'inactive';
        this.ondataavailable({ data: new Blob(['synthetic audio']) });
        this.onstop();
      }
    }
    function AudioContext() {
      this.createMediaStreamSource = () => ({
        connect: vi.fn(),
        disconnect: vi.fn(),
      });
      this.createAnalyser = () => ({
        fftSize: 1024,
        getByteTimeDomainData: values => values.fill(amplitude),
      });
      this.close = () => Promise.resolve();
    }
    vi.stubGlobal('MediaRecorder', Recorder);
    vi.stubGlobal('SpeechSynthesisUtterance', function Utterance(text) {
      return { text };
    });
    vi.stubGlobal('window', {
      MediaRecorder: Recorder,
      AudioContext,
      speechSynthesis: {
        cancel: vi.fn(),
        speak: vi.fn(utterance => {
          utterance.onstart();
        }),
      },
    });
    vi.stubGlobal('navigator', {
      mediaDevices: {
        getUserMedia: vi.fn(async () => ({ getTracks: () => [track] })),
      },
    });
    approval = ref(false);
    inCall = ref(false);
    context = ref('account-a:conversation-a');
    visible = ref(true);
    canSubmit = ref(true);
    onSubmit = vi.fn(async () => true);
    scope = effectScope();
    scope.run(() => {
      voice = useNicoVoiceConversation({
        onTranscript: vi.fn(),
        onSubmit,
        transcribe: vi.fn(async () => ({
          data: { text: 'Synthetic internal request' },
        })),
        inCall,
        context,
        canSubmit,
        active: visible,
        pendingApproval: approval,
      });
    });
  });
  afterEach(() => {
    scope.stop();
    vi.useRealTimers();
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it('stays off until explicitly started and ends a spoken turn after silence', async () => {
    expect(navigator.mediaDevices.getUserMedia).not.toHaveBeenCalled();
    expect(voice.continuousActive.value).toBe(false);
    await voice.startConversation();
    amplitude = 150;
    await vi.advanceTimersByTimeAsync(300);
    amplitude = 128;
    await vi.advanceTimersByTimeAsync(1600);
    expect(voice.reviewing.value).toBe(true);
    expect(onSubmit).not.toHaveBeenCalled();
    await vi.advanceTimersByTimeAsync(1600);
    expect(onSubmit).toHaveBeenCalledOnce();
    expect(voice.continuousTurns.value).toBe(1);
  });

  it.each(['approval', 'call', 'context', 'hidden'])(
    'stops capture and automatic continuation for %s',
    async event => {
      await voice.startConversation();
      if (event === 'approval') approval.value = true;
      if (event === 'call') inCall.value = true;
      if (event === 'context') context.value = 'account-b:conversation-b';
      if (event === 'hidden') visible.value = false;
      await vi.advanceTimersByTimeAsync(5000);
      expect(voice.continuousActive.value).toBe(false);
      expect(voice.listening.value).toBe(false);
      expect(track.stop).toHaveBeenCalled();
      expect(onSubmit).not.toHaveBeenCalled();
      expect(navigator.mediaDevices.getUserMedia).toHaveBeenCalledOnce();
    }
  );

  it('does not resume during operator review or after manual cancellation', async () => {
    await voice.startConversation();
    recorders.at(-1).stop();
    await vi.advanceTimersByTimeAsync(0);
    expect(voice.reviewing.value).toBe(true);
    voice.cancelReview();
    await vi.advanceTimersByTimeAsync(5000);
    expect(onSubmit).not.toHaveBeenCalled();
    expect(voice.continuousActive.value).toBe(false);
  });

  it('finishes the current utterance from the square button without opening another recording', async () => {
    await voice.startConversation();
    await voice.start();
    await vi.advanceTimersByTimeAsync(0);
    expect(voice.reviewing.value).toBe(true);
    expect(voice.continuousActive.value).toBe(true);
    expect(navigator.mediaDevices.getUserMedia).toHaveBeenCalledOnce();
    expect(onSubmit).not.toHaveBeenCalled();
    await vi.advanceTimersByTimeAsync(1600);
    expect(onSubmit).toHaveBeenCalledOnce();
  });

  it('stops after twelve turns instead of capturing indefinitely', async () => {
    await voice.startConversation();
    for (let turn = 0; turn < 12; turn += 1) {
      expect(voice.listening.value).toBe(true);
      recorders.at(-1).stop();
      // eslint-disable-next-line no-await-in-loop -- Twelve sequential operator turns must finish one at a time.
      await vi.advanceTimersByTimeAsync(2200);
    }
    expect(onSubmit).toHaveBeenCalledTimes(12);
    expect(voice.continuousActive.value).toBe(false);
    await vi.advanceTimersByTimeAsync(10000);
    expect(navigator.mediaDevices.getUserMedia).toHaveBeenCalledTimes(12);
  });

  it('does not resume the microphone while reading the response', async () => {
    onSubmit.mockImplementation(async () => {
      voice.speak('Synthetic private response');
      return true;
    });
    await voice.startConversation();
    recorders.at(-1).stop();
    await vi.advanceTimersByTimeAsync(7000);
    expect(navigator.mediaDevices.getUserMedia).toHaveBeenCalledOnce();
    expect(voice.speaking.value).toBe(true);
    window.speechSynthesis.speak.mock.calls.at(-1)[0].onend();
    await vi.advanceTimersByTimeAsync(600);
    expect(navigator.mediaDevices.getUserMedia).toHaveBeenCalledTimes(2);
  });
  it('stops when the internal request was not confirmed and never retries it automatically', async () => {
    onSubmit.mockResolvedValue(false);
    await voice.startConversation();
    recorders.at(-1).stop();
    await vi.advanceTimersByTimeAsync(7000);
    expect(onSubmit).toHaveBeenCalledOnce();
    expect(voice.continuousActive.value).toBe(false);
    expect(navigator.mediaDevices.getUserMedia).toHaveBeenCalledOnce();
  });
  it('expires after five minutes and releases a late permission grant after a context switch', async () => {
    await voice.startConversation();
    await vi.advanceTimersByTimeAsync(300000);
    expect(voice.continuousActive.value).toBe(false);
    let grant;
    navigator.mediaDevices.getUserMedia.mockImplementation(
      () =>
        new Promise(resolve => {
          grant = resolve;
        })
    );
    const start = voice.startConversation();
    context.value = 'another-account:another-conversation';
    grant({ getTracks: () => [track] });
    await start;
    expect(voice.continuousActive.value).toBe(false);
    expect(voice.listening.value).toBe(false);
    expect(track.stop).toHaveBeenCalled();
  });
});
