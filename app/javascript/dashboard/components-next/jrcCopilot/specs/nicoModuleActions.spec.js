/* global axios */
import { runNicoModuleAction } from '../nicoModuleActions';
import api from '../../../api/jrcNicoOperations';

describe('NICO authenticated module actions', () => {
  beforeEach(() => {
    global.axios = {
      post: vi.fn().mockResolvedValue({ data: { id: 42 } }),
      patch: vi.fn().mockResolvedValue({ data: { id: 42 } }),
    };
  });
  afterEach(() => {
    delete global.axios;
  });
  it('uses the existing proposal item endpoint and only the reviewed item', async () => {
    await runNicoModuleAction(7, {
      operation: 'add_proposal_item',
      parameters: { proposal_id: 12, product_id: 4, quantity: 2 },
    });
    expect(axios.post).toHaveBeenCalledWith(
      '/api/v1/accounts/7/crm/proposals/12/items',
      { item: { product_id: 4, quantity: 2 } }
    );
  });
  it('creates a project task once using the native task wrapper and nested receipt', async () => {
    axios.post.mockResolvedValue({
      data: { data: { id: 42, status: 'backlog' } },
    });
    const result = await runNicoModuleAction(7, {
      operation: 'create_project_task',
      parameters: {
        project_id: 12,
        title: 'Implementation',
        board_column_id: 3,
      },
    });
    expect(axios.post).toHaveBeenCalledExactlyOnceWith(
      '/api/v1/accounts/7/projects/projects/12/tasks',
      { task: { title: 'Implementation', board_column_id: 3 } }
    );
    expect(result).toContain('registro 42');
    expect(result).toContain('backlog');
  });
  it('preserves version zero and explicit removal in the native task edit', async () => {
    await runNicoModuleAction(7, {
      operation: 'update_project_task',
      parameters: {
        project_id: 12,
        task_id: 42,
        lock_version: 0,
        title: 'Revised',
        clear_assignee: true,
        clear_parent: true,
      },
    });
    expect(axios.patch).toHaveBeenCalledExactlyOnceWith(
      '/api/v1/accounts/7/projects/projects/12/tasks/42',
      {
        task: {
          lock_version: 0,
          title: 'Revised',
          assignee_id: null,
          parent_id: null,
        },
      }
    );
  });
  it('does not retry an ambiguous task creation failure', async () => {
    const error = Object.assign(new Error('network lost'), {
      isAxiosError: true,
    });
    axios.post.mockRejectedValue(error);
    await expect(
      runNicoModuleAction(7, {
        operation: 'create_project_task',
        parameters: { project_id: 12, title: 'Implementation' },
      })
    ).rejects.toBe(error);
    expect(axios.post).toHaveBeenCalledTimes(1);
  });
  it('uses the profile availability wrapper required by the controller', async () => {
    await runNicoModuleAction(7, {
      operation: 'set_availability',
      parameters: { availability: 'busy' },
    });
    expect(axios.post).toHaveBeenCalledWith('/api/v1/profile/availability', {
      profile: { account_id: 7, availability: 'busy' },
    });
  });
  it('sends catalog and inbox edits through their existing module APIs', async () => {
    await runNicoModuleAction(7, {
      operation: 'update_product',
      parameters: { product_id: 12, name: 'Plano revisado', active: false },
    });
    expect(axios.patch).toHaveBeenLastCalledWith(
      '/api/v1/accounts/7/crm/products/12',
      {
        product: { name: 'Plano revisado', active: false },
      }
    );
    await runNicoModuleAction(7, {
      operation: 'update_inbox_settings',
      parameters: { inbox_id: 9, greeting_enabled: false },
    });
    expect(axios.patch).toHaveBeenLastCalledWith(
      '/api/v1/accounts/7/inboxes/9',
      { greeting_enabled: false }
    );
  });
  it('propagates module rejection and refuses unknown operations', async () => {
    axios.patch.mockRejectedValue(new Error('Aprovação bloqueada'));
    await expect(
      runNicoModuleAction(7, {
        operation: 'update_proposal',
        parameters: { proposal_id: 12, title: 'Nova' },
      })
    ).rejects.toThrow('bloqueada');
    await expect(
      runNicoModuleAction(7, { operation: 'arbitrary_url', parameters: {} })
    ).rejects.toThrow('não disponível');
  });
  it('does not claim WhatsApp success when a channel did not return a call', async () => {
    await expect(
      runNicoModuleAction(
        7,
        { operation: 'whatsapp_call', parameters: { conversation_id: 9 } },
        { whatsapp: { initiateOutboundCall: async () => null } }
      )
    ).rejects.toThrow('não foi iniciada');
  });
  it('keeps operations and audio scoped without overriding application authentication', async () => {
    await api.ask(7, { message: 'Oi' });
    expect(axios.post).toHaveBeenCalledWith(
      '/api/v1/accounts/7/jrc_nico/operations/ask',
      { message: 'Oi' }
    );
    const signal = new AbortController().signal;
    await api.transcribe(
      7,
      new Blob(['audio'], { type: 'audio/webm' }),
      signal
    );
    expect(axios.post).toHaveBeenLastCalledWith(
      '/api/v1/accounts/7/jrc_nico/operations/transcribe',
      expect.any(FormData),
      { signal }
    );
  });
});
