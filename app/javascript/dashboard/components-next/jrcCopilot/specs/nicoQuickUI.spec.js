// @vitest-environment jsdom
import { defineComponent, reactive, ref, nextTick } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import JrcCopilotLauncher from '../JrcCopilotLauncher.vue';
import JrcCopilotPanel from '../JrcCopilotPanel.vue';
import { useJrcCopilot } from '../useJrcCopilot';
import api from 'dashboard/api/jrcNicoOperations';
import translations from 'dashboard/i18n/locale/en/jrcNico.json';

let route;
let calls;
let sip;
let currentChat;
vi.mock('vue-router', () => ({
  useRoute: () => route,
  useRouter: () => ({ hasRoute: () => true, push: vi.fn() }),
}));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => currentChat,
}));
vi.mock('dashboard/stores/calls', () => ({ useCallsStore: () => calls }));
vi.mock('dashboard/routes/dashboard/webphone/useSipWebphone', () => ({
  useSipWebphone: () => sip,
}));
vi.mock('dashboard/composables/useWhatsappCallSession', () => ({
  useWhatsappCallSession: () => ({}),
}));
vi.mock('dashboard/api/videoConferenceSettings', () => ({ default: {} }));
vi.mock('dashboard/helper/videoConference', () => ({
  openVideoConferencePopup: vi.fn(),
}));
vi.mock('../nicoBrowserActions', () => ({ runNicoBrowserAction: vi.fn() }));
vi.mock('../nicoModuleActions', () => ({ runNicoModuleAction: vi.fn() }));
vi.mock('../NicoConversationPanel.vue', () => ({
  default: { template: '<div />' },
}));
vi.mock('../NicoKnowledgePanel.vue', () => ({
  default: { template: '<div />' },
}));
vi.mock('dashboard/api/jrcNicoOperations', () => ({
  default: {
    show: vi.fn(),
    notices: vi.fn(),
    readNotice: vi.fn(),
    ask: vi.fn(),
    command: vi.fn(),
    transcribe: vi.fn(),
    conversations: vi.fn(),
  },
}));

describe('Quick NICO and Full Copilot use one operator session', () => {
  let wrapper;
  let snapshot;
  let noticeList;
  let track;
  let ui;
  beforeEach(async () => {
    vi.useFakeTimers();
    vi.clearAllMocks();
    Object.defineProperty(document, 'visibilityState', {
      configurable: true,
      value: 'visible',
    });
    Object.defineProperty(window, 'innerWidth', {
      configurable: true,
      value: 1366,
      writable: true,
    });
    route = reactive({ params: { accountId: '1', conversation_id: '14' } });
    calls = reactive({ hasActiveCall: false, hasIncomingCall: false });
    sip = { hasCall: ref(false), registered: ref(true) };
    currentChat = ref({ id: 14, meta: { sender: { name: 'Marina' } } });
    snapshot = {
      messages: [],
      commands: [],
      delegations: [],
      suggestions: [],
      tools: [{ name: 'create_contact', description: 'Criar contato' }],
    };
    noticeList = [];
    api.show.mockImplementation(async () => ({ data: snapshot }));
    api.notices.mockImplementation(async () => ({
      data: { notices: noticeList },
    }));
    api.readNotice.mockImplementation(async () => {
      noticeList = noticeList.map(notice => ({ ...notice, unread: false }));
      return { data: { notices: noticeList } };
    });
    api.ask.mockImplementation(async (_id, request) => {
      snapshot = {
        ...snapshot,
        messages: [
          { role: 'user', content: request.message },
          {
            role: 'assistant',
            content: 'Confira os dados para criar o contato.',
          },
        ],
        commands: [
          {
            id: 101,
            status: 'awaiting_confirmation',
            tool: 'create_contact',
            arguments: { name: 'Pessoa de teste' },
          },
        ],
      };
      return { data: snapshot };
    });
    api.command.mockImplementation(async () => {
      snapshot = {
        ...snapshot,
        commands: [
          {
            ...snapshot.commands[0],
            status: 'succeeded',
            result: {
              record: { id: 5, name: 'Pessoa de teste' },
              message: 'Contato criado.',
            },
          },
        ],
      };
      return { data: snapshot };
    });
    api.transcribe.mockResolvedValue({
      data: { text: 'Crie um contato de teste' },
    });
    track = { stop: vi.fn() };
    class Recorder {
      static isTypeSupported() {
        return true;
      }

      constructor() {
        this.state = 'inactive';
      }

      start() {
        this.state = 'recording';
      }

      stop() {
        this.state = 'inactive';
        this.ondataavailable({ data: new Blob(['audio']) });
        this.onstop();
      }
    }
    vi.stubGlobal('MediaRecorder', Recorder);
    Object.defineProperty(navigator, 'mediaDevices', {
      configurable: true,
      value: {
        getUserMedia: vi.fn().mockResolvedValue({ getTracks: () => [track] }),
      },
    });
    Element.prototype.scrollIntoView = vi.fn();
    ui = useJrcCopilot();
    ui.close();
    ui.pendingPrompt.value = '';
    ui.notices.value = [];
    ui.focusedNoticeId.value = null;
    const host = defineComponent({
      components: { JrcCopilotLauncher, JrcCopilotPanel },
      // eslint-disable-next-line vue/no-unused-properties -- Consumed by the inline host template below.
      props: { docked: { type: Boolean, default: false } },
      template:
        '<div><JrcCopilotLauncher :docked="docked" /><JrcCopilotPanel /></div>',
    });
    wrapper = mount(host, {
      attachTo: document.body,
      global: {
        plugins: [
          createI18n({
            legacy: false,
            locale: 'en',
            messages: { en: translations },
          }),
        ],
      },
    });
    await flushPromises();
  });
  it('keeps the existing notice session and quick panel when docked in the global rail', async () => {
    const launcher = wrapper.findComponent(JrcCopilotLauncher);
    const reads = api.notices.mock.calls.length;
    await wrapper.setProps({ docked: true });
    expect(launcher.classes()).toContain('relative');
    expect(launcher.classes()).not.toContain('absolute');
    await launcher
      .get('button[aria-controls="nico-quick-panel"]')
      .trigger('click');
    await flushPromises();
    expect(ui.mode.value).toBe('quick');
    expect(api.notices.mock.calls.length - reads).toBeLessThanOrEqual(1);
    expect(wrapper.findAllComponents(JrcCopilotLauncher)).toHaveLength(1);
  });

  afterEach(() => {
    wrapper.unmount();
    ui.close();
    vi.useRealTimers();
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
    document.body.innerHTML = '';
  });

  it('shows the safe server error in Quick and Full without executing a tool', async () => {
    const message =
      'O NICO não conseguiu interpretar os dados. Nenhuma alteração foi realizada.';
    api.ask.mockRejectedValueOnce({
      response: { data: { error: 'tool_arguments_invalid', message } },
    });
    ui.openQuick();
    await flushPromises();
    await wrapper.get('textarea').setValue('Crie um contato');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(wrapper.text()).toContain(message);
    expect(api.command).not.toHaveBeenCalled();
    await wrapper.get('[aria-label="Abrir Full Copilot"]').trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain(message);
  });

  it('preserves the draft and request identity after a failed send', async () => {
    ui.openQuick();
    await flushPromises();
    api.ask.mockRejectedValueOnce(new Error('network unavailable'));
    await wrapper.get('textarea').setValue('Crie um contato');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    const firstRequest = api.ask.mock.calls[0][1];
    expect(wrapper.get('textarea').element.value).toBe('Crie um contato');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(api.ask.mock.calls[1][1].request_id).toBe(firstRequest.request_id);
    expect(wrapper.get('textarea').element.value).toBe('');
  });

  it('clears only a synchronization error when the next load succeeds', async () => {
    api.show.mockRejectedValueOnce(new Error('temporary failure'));
    ui.openQuick();
    await flushPromises();
    expect(wrapper.text()).toContain(translations.JRC_NICO.OPERATOR.LOAD_ERROR);
    await vi.advanceTimersByTimeAsync(5000);
    await flushPromises();
    expect(wrapper.text()).not.toContain(
      translations.JRC_NICO.OPERATOR.LOAD_ERROR
    );
  });

  it('does not poll the closed idle session and pauses notices in a hidden tab', async () => {
    const initialShows = api.show.mock.calls.length;
    await vi.advanceTimersByTimeAsync(30000);
    expect(api.show).toHaveBeenCalledTimes(initialShows);
    expect(api.notices).toHaveBeenCalledTimes(2);
    Object.defineProperty(document, 'visibilityState', {
      configurable: true,
      value: 'hidden',
    });
    document.dispatchEvent(new Event('visibilitychange'));
    await vi.advanceTimersByTimeAsync(60000);
    expect(api.notices).toHaveBeenCalledTimes(2);
    expect(api.show).toHaveBeenCalledTimes(initialShows);
  });

  it('keeps polling an active delegation while the panel is closed', async () => {
    snapshot.delegations = [{ id: 1, status: 'active' }];
    const initialShows = api.show.mock.calls.length;
    await vi.advanceTimersByTimeAsync(5000);
    expect(api.show).toHaveBeenCalledTimes(initialShows + 1);
  });

  it('does not abort or duplicate a slow session refresh', async () => {
    let resolveLoad;
    api.show.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolveLoad = resolve;
        })
    );
    ui.openQuick();
    await flushPromises();
    const callsBeforeTick = api.show.mock.calls.length;
    const signal = api.show.mock.calls.at(-1)[1];
    await vi.advanceTimersByTimeAsync(15000);
    expect(api.show).toHaveBeenCalledTimes(callsBeforeTick);
    expect(signal.aborted).toBe(false);
    resolveLoad({ data: snapshot });
    await flushPromises();
  });

  it('shows a partial workflow and each step outcome in Quick and Full', async () => {
    snapshot.workflow = {
      state: 'partial',
      completed_count: 1,
      steps: [
        { id: 1, status: 'succeeded', reply: 'Lead criado' },
        { id: 2, status: 'failed', reply: 'Envio recusado' },
      ],
    };
    ui.openQuick();
    await flushPromises();
    expect(
      wrapper.get('[data-testid="nico-workflow-summary"]').text()
    ).toContain('Envio recusado');
    expect(wrapper.text()).toContain(translations.JRC_NICO.WORKFLOW.partial);
    await wrapper.get('[aria-label="Abrir Full Copilot"]').trigger('click');
    await flushPromises();
    expect(
      wrapper.get('[data-testid="nico-workflow-summary"]').text()
    ).toContain('Falhou');
  });

  it('opens Quick from the mascot without asking or executing on hover', async () => {
    const mascot = wrapper.get('[aria-label="Abrir assistente NICO"]');
    await mascot.trigger('mouseenter');
    expect(api.ask).not.toHaveBeenCalled();
    await mascot.trigger('click');
    await flushPromises();
    expect(ui.mode.value).toBe('quick');
    expect(wrapper.find('#nico-quick-panel').exists()).toBe(true);
    expect(wrapper.find('#nico-operator-panel').exists()).toBe(false);
    await vi.advanceTimersByTimeAsync(200);
    expect(
      wrapper
        .find('[aria-label="Recolher balão e manter aviso pendente"]')
        .exists()
    ).toBe(false);
    expect(document.activeElement).toBe(wrapper.get('textarea').element);
  });

  it('expands Quick into Full while preserving the draft and friendly conversation context', async () => {
    ui.openQuick();
    await flushPromises();
    await wrapper.get('textarea').setValue('Minha tarefa ainda não enviada');
    expect(wrapper.text()).toContain('Contexto: Marina');
    await wrapper.get('[aria-label="Abrir Full Copilot"]').trigger('click');
    await flushPromises();
    expect(ui.mode.value).toBe('full');
    expect(wrapper.find('#nico-quick-panel').exists()).toBe(false);
    expect(wrapper.get('#nico-operator-panel').exists()).toBe(true);
    expect(wrapper.get('textarea').element.value).toBe(
      'Minha tarefa ainda não enviada'
    );
    expect(document.activeElement).toBe(
      wrapper.get('#nico-operator-panel').element
    );
    expect(api.ask).not.toHaveBeenCalled();
  });

  it('closing Full with Escape returns keyboard focus to the mascot', async () => {
    ui.open();
    await flushPromises();
    await wrapper
      .get('#nico-operator-panel')
      .trigger('keydown', { key: 'Escape' });
    await flushPromises();
    expect(ui.mode.value).toBe('closed');
    expect(document.activeElement).toBe(
      wrapper.get('[aria-label="Abrir assistente NICO"]').element
    );
  });

  it('closing Quick with Escape cancels its review and returns focus', async () => {
    ui.openQuick();
    await flushPromises();
    await wrapper.get('[aria-label="Falar com NICO"]').trigger('click');
    await flushPromises();
    await wrapper.get('[aria-label="Parar escuta"]').trigger('click');
    await flushPromises();
    await wrapper
      .get('#nico-quick-panel')
      .trigger('keydown', { key: 'Escape' });
    await vi.advanceTimersByTimeAsync(2000);
    expect(api.ask).not.toHaveBeenCalled();
    expect(ui.mode.value).toBe('closed');
    expect(document.activeElement).toBe(
      wrapper.get('[aria-label="Abrir assistente NICO"]').element
    );
  });

  it('auto submits a voice request once but only explicit confirmation executes a mutation', async () => {
    ui.openQuick();
    await flushPromises();
    await wrapper.get('[aria-label="Falar com NICO"]').trigger('click');
    await flushPromises();
    expect(
      wrapper
        .get('[data-testid="nico-interaction-status"]')
        .attributes('data-state')
    ).toBe('listening');
    await wrapper.get('[aria-label="Parar escuta"]').trigger('click');
    await flushPromises();
    expect(wrapper.get('textarea').element.value).toBe(
      'Crie um contato de teste'
    );
    expect(wrapper.find('[data-testid="nico-voice-review"]').exists()).toBe(
      true
    );
    expect(api.ask).not.toHaveBeenCalled();
    await vi.advanceTimersByTimeAsync(1500);
    await flushPromises();
    expect(api.ask).toHaveBeenCalledOnce();
    expect(api.ask).toHaveBeenCalledWith(
      1,
      expect.objectContaining({
        message: 'Crie um contato de teste',
        conversation_id: 14,
        request_id: expect.any(String),
      })
    );
    expect(api.command).not.toHaveBeenCalled();
    expect(
      wrapper
        .get('[data-testid="nico-interaction-status"]')
        .attributes('data-state')
    ).toBe('confirmation');
    await wrapper.get('[aria-label="Abrir Full Copilot"]').trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain('Pessoa de teste');
    await wrapper.get('[data-nico-command] button').trigger('click');
    await flushPromises();
    expect(api.command).toHaveBeenCalledExactlyOnceWith(1, 101, 'confirm');
    expect(
      wrapper
        .get('[data-testid="nico-interaction-status"]')
        .attributes('data-state')
    ).toBe('success');
  });

  it('manual send during voice review cannot be followed by a duplicate auto ask', async () => {
    ui.openQuick();
    await flushPromises();
    await wrapper.get('[aria-label="Falar com NICO"]').trigger('click');
    await flushPromises();
    await wrapper.get('[aria-label="Parar escuta"]').trigger('click');
    await flushPromises();
    await wrapper.get('form').trigger('submit');
    await wrapper.get('form').trigger('submit');
    await vi.advanceTimersByTimeAsync(2000);
    expect(api.ask).toHaveBeenCalledOnce();
    expect(api.command).not.toHaveBeenCalled();
  });

  it('editing the transcript cancels auto send and uses the edited manual text', async () => {
    ui.openQuick();
    await flushPromises();
    await wrapper.get('[aria-label="Falar com NICO"]').trigger('click');
    await flushPromises();
    await wrapper.get('[aria-label="Parar escuta"]').trigger('click');
    await flushPromises();
    await wrapper.get('textarea').setValue('Procure a Marina');
    await vi.advanceTimersByTimeAsync(2000);
    expect(api.ask).not.toHaveBeenCalled();
    await wrapper.get('form').trigger('submit');
    expect(api.ask).toHaveBeenCalledWith(
      1,
      expect.objectContaining({ message: 'Procure a Marina' })
    );
  });

  it('the review cancel button prevents auto send while keeping the draft', async () => {
    ui.openQuick();
    await flushPromises();
    await wrapper.get('[aria-label="Falar com NICO"]').trigger('click');
    await flushPromises();
    await wrapper.get('[aria-label="Parar escuta"]').trigger('click');
    await flushPromises();
    const cancel = wrapper
      .findAll('button')
      .find(button => button.text() === 'Cancelar envio automático');
    await cancel.trigger('click');
    await vi.advanceTimersByTimeAsync(2000);
    expect(api.ask).not.toHaveBeenCalled();
    expect(wrapper.get('textarea').element.value).toBe(
      'Crie um contato de teste'
    );
  });

  it('switching account clears the voice draft and prevents a stale request', async () => {
    ui.openQuick();
    await flushPromises();
    await wrapper.get('[aria-label="Falar com NICO"]').trigger('click');
    await flushPromises();
    await wrapper.get('[aria-label="Parar escuta"]').trigger('click');
    await flushPromises();
    route.params.accountId = '2';
    await vi.advanceTimersByTimeAsync(2000);
    expect(api.ask).not.toHaveBeenCalled();
    expect(wrapper.get('textarea').element.value).toBe('');
  });

  it('an incoming call stops capture and disables the microphone in both views', async () => {
    ui.openQuick();
    await flushPromises();
    await wrapper.get('[aria-label="Falar com NICO"]').trigger('click');
    await flushPromises();
    calls.hasIncomingCall = true;
    await nextTick();
    expect(track.stop).toHaveBeenCalledOnce();
    expect(api.transcribe).not.toHaveBeenCalled();
    expect(wrapper.get('[aria-label="Falar com NICO"]').element.disabled).toBe(
      true
    );
    await wrapper.get('[aria-label="Abrir Full Copilot"]').trigger('click');
    expect(wrapper.get('[aria-label="Falar com NICO"]').element.disabled).toBe(
      true
    );
  });

  it('keeps unread notices while moving from balloon to Quick and Full', async () => {
    noticeList = [
      {
        id: 7,
        updated_at: 'one',
        contact_name: 'Marina',
        body: 'Revisar oportunidade',
        unread: true,
      },
    ];
    await vi.advanceTimersByTimeAsync(30000);
    expect(wrapper.text()).toContain('Revisar oportunidade');
    await wrapper
      .get('[aria-label="Recolher balão e manter aviso pendente"]')
      .trigger('click');
    expect(wrapper.find('[aria-label="Avisos não lidos: 1"]').exists()).toBe(
      true
    );
    await wrapper.get('[aria-label="Abrir assistente NICO"]').trigger('click');
    await flushPromises();
    await vi.advanceTimersByTimeAsync(200);
    expect(
      wrapper
        .find('[aria-label="Recolher balão e manter aviso pendente"]')
        .exists()
    ).toBe(false);
    const noticeButton = wrapper
      .findAll('button')
      .find(button => button.text().includes('Ver avisos pendentes'));
    await noticeButton.trigger('click');
    await flushPromises();
    expect(ui.mode.value).toBe('full');
    expect(ui.focusedNoticeId.value).toBe(7);
    expect(wrapper.text()).toContain('Revisar oportunidade');
    expect(api.command).not.toHaveBeenCalled();
  });

  it('the notice balloon pauses its timer while focused and read remains an explicit action', async () => {
    noticeList = [
      {
        id: 8,
        updated_at: 'two',
        contact_name: 'Marina',
        body: 'Novo aviso',
        unread: true,
      },
    ];
    await vi.advanceTimersByTimeAsync(30000);
    const dismiss = wrapper.get(
      '[aria-label="Recolher balão e manter aviso pendente"]'
    );
    await dismiss.trigger('focusin');
    await vi.advanceTimersByTimeAsync(13000);
    expect(
      wrapper
        .find('[aria-label="Recolher balão e manter aviso pendente"]')
        .exists()
    ).toBe(true);
    const read = wrapper
      .findAll('button')
      .find(button => button.text() === 'Marcar aviso como lido');
    await read.trigger('click');
    await flushPromises();
    expect(api.readNotice).toHaveBeenCalledExactlyOnceWith(1, 8);
    expect(wrapper.find('[aria-label="Avisos não lidos: 1"]').exists()).toBe(
      false
    );
  });

  it('uses the backend outcome for success, failure and read-only results', async () => {
    ui.openQuick();
    await flushPromises();
    api.ask.mockResolvedValueOnce({
      data: {
        ...snapshot,
        commands: [{ id: 10, status: 'failed', reply: 'Não concluído' }],
      },
    });
    await wrapper.get('textarea').setValue('Consulte contatos');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(
      wrapper
        .get('[data-testid="nico-interaction-status"]')
        .attributes('data-state')
    ).toBe('error');
    api.ask.mockResolvedValueOnce({
      data: {
        ...snapshot,
        messages: [{ role: 'assistant', content: 'Localizei Marina.' }],
        commands: [{ id: 11, status: 'succeeded', tool: 'search_contacts' }],
      },
    });
    await wrapper.get('textarea').setValue('Busque Marina');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(wrapper.text()).toContain('Localizei Marina.');
    expect(
      wrapper
        .get('[data-testid="nico-interaction-status"]')
        .attributes('data-state')
    ).toBe('success');
    expect(api.command).not.toHaveBeenCalled();
  });

  it('does not label a clarification reply as a completed action', async () => {
    api.ask.mockResolvedValueOnce({
      data: {
        ...snapshot,
        messages: [{ role: 'assistant', content: 'Qual é o nome do contato?' }],
        commands: [{ id: 12, status: 'succeeded', tool: null }],
      },
    });
    ui.openQuick();
    await flushPromises();
    await wrapper.get('textarea').setValue('Crie um contato');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(wrapper.text()).toContain('Qual é o nome do contato?');
    expect(wrapper.text()).toContain('Resposta pronta para você');
    expect(wrapper.text()).not.toContain('Pedido concluído');
    expect(api.command).not.toHaveBeenCalled();
  });

  it('can continue by text after microphone permission was denied', async () => {
    navigator.mediaDevices.getUserMedia.mockRejectedValueOnce(
      new Error('denied')
    );
    ui.openQuick();
    await flushPromises();
    await wrapper.get('[aria-label="Falar com NICO"]').trigger('click');
    await flushPromises();
    expect(
      wrapper
        .get('[data-testid="nico-interaction-status"]')
        .attributes('data-state')
    ).toBe('error');
    await wrapper.get('textarea').setValue('Crie um contato');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(
      wrapper
        .get('[data-testid="nico-interaction-status"]')
        .attributes('data-state')
    ).toBe('confirmation');
    expect(api.ask).toHaveBeenCalledOnce();
    expect(api.command).not.toHaveBeenCalled();
  });

  it('all listening animations are gated by reduced-motion support', async () => {
    ui.openQuick();
    await flushPromises();
    await wrapper.get('[aria-label="Falar com NICO"]').trigger('click');
    await flushPromises();
    const animations = wrapper
      .findAll('*')
      .flatMap(element => element.classes())
      .filter(name => name.includes('animate-'));
    expect(animations.length).toBeGreaterThan(0);
    expect(animations.every(name => name.startsWith('motion-safe:'))).toBe(
      true
    );
  });

  it('shows understanding and working while waiting, never completion before the backend confirms it', async () => {
    ui.openQuick();
    await flushPromises();
    let reply;
    api.ask.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          reply = resolve;
        })
    );
    await wrapper.get('textarea').setValue('Crie um contato');
    await wrapper.get('form').trigger('submit');
    expect(
      wrapper
        .get('[data-testid="nico-interaction-status"]')
        .attributes('data-state')
    ).toBe('submitting');
    snapshot = {
      ...snapshot,
      commands: [
        {
          id: 20,
          status: 'awaiting_confirmation',
          tool: 'create_contact',
          arguments: { name: 'Teste' },
        },
      ],
    };
    reply({ data: snapshot });
    await flushPromises();
    await wrapper.get('[aria-label="Abrir Full Copilot"]').trigger('click');
    await flushPromises();
    let complete;
    api.command.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          complete = resolve;
        })
    );
    await wrapper.get('[data-nico-command] button').trigger('click');
    expect(
      wrapper
        .get('[data-testid="nico-interaction-status"]')
        .attributes('data-state')
    ).toBe('working');
    complete({
      data: {
        ...snapshot,
        commands: [{ ...snapshot.commands[0], status: 'unknown' }],
      },
    });
    await flushPromises();
    expect(
      wrapper
        .get('[data-testid="nico-interaction-status"]')
        .attributes('data-state')
    ).toBe('unknown');
  });

  it('ignores an old read response that arrives after the current request prepared an action', async () => {
    let oldRead;
    api.show.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          oldRead = resolve;
        })
    );
    ui.openQuick();
    await nextTick();
    await wrapper.get('textarea').setValue('Crie um contato');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(
      wrapper
        .get('[data-testid="nico-interaction-status"]')
        .attributes('data-state')
    ).toBe('confirmation');
    oldRead({ data: { ...snapshot, commands: [], messages: [] } });
    await flushPromises();
    expect(
      wrapper
        .get('[data-testid="nico-interaction-status"]')
        .attributes('data-state')
    ).toBe('confirmation');
  });

  it('manual typing during transcription aborts the upload and rejects the late transcript', async () => {
    let reply;
    api.transcribe.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          reply = resolve;
        })
    );
    ui.openQuick();
    await flushPromises();
    await wrapper.get('[aria-label="Falar com NICO"]').trigger('click');
    await flushPromises();
    await wrapper.get('[aria-label="Parar escuta"]').trigger('click');
    await flushPromises();
    expect(
      wrapper
        .get('[data-testid="nico-interaction-status"]')
        .attributes('data-state')
    ).toBe('transcribing');
    const signal = api.transcribe.mock.calls[0][2];
    await wrapper.get('textarea').setValue('Prefiro este pedido digitado');
    expect(signal.aborted).toBe(true);
    reply({ data: { text: 'Transcrição antiga' } });
    await vi.advanceTimersByTimeAsync(2000);
    expect(wrapper.get('textarea').element.value).toBe(
      'Prefiro este pedido digitado'
    );
    expect(api.ask).not.toHaveBeenCalled();
  });

  it('expanding during voice review retains one timer and the same request context', async () => {
    ui.openQuick();
    await flushPromises();
    await wrapper.get('[aria-label="Falar com NICO"]').trigger('click');
    await flushPromises();
    await wrapper.get('[aria-label="Parar escuta"]').trigger('click');
    await flushPromises();
    await wrapper.get('[aria-label="Abrir Full Copilot"]').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-testid="nico-voice-review"]').exists()).toBe(
      true
    );
    await vi.advanceTimersByTimeAsync(2000);
    expect(api.ask).toHaveBeenCalledOnce();
    expect(api.ask).toHaveBeenCalledWith(
      1,
      expect.objectContaining({ conversation_id: 14 })
    );
    expect(api.command).not.toHaveBeenCalled();
  });

  it('preserves callers that open Full directly with a pending prompt', async () => {
    ui.openWithPrompt('Consulte minhas atividades');
    await flushPromises();
    expect(ui.mode.value).toBe('full');
    expect(ui.pendingPrompt.value).toBe('');
    expect(api.ask).toHaveBeenCalledOnce();
  });
});
