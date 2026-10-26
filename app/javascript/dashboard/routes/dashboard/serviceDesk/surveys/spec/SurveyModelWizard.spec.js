import { afterEach, describe, expect, it, vi } from 'vitest';
import { flushPromises, mount } from '@vue/test-utils';
import SurveyModelWizard from '../SurveyModelWizard.vue';
import { newModel } from '../modelForm';
import { surveyModelEditorOpen } from '../presentation';

const unit = {
  id: 1,
  name: 'Synthetic unit',
  operator_id: 1,
  operator_name: 'Synthetic operator',
};
const options = {
  units: [unit],
  teams: [],
  executors: [{ id: 1, name: 'Synthetic operator' }],
  inboxes: [],
  ticket_types: [],
  queues: [],
  priorities: [],
  timezone: 'America/Sao_Paulo',
  role: 'administrator',
  automation_enabled: false,
};
let wrapper;
afterEach(() => {
  wrapper?.unmount();
  wrapper = null;
  vi.restoreAllMocks();
  document.body.innerHTML = '';
});
function mountEditor(api = {}, record = null) {
  wrapper = mount(SurveyModelWizard, {
    attachTo: document.body,
    props: { accountId: 1, unit, options, api, record },
    global: { stubs: { Teleport: true, SurveyRuleTemplatePanel: true } },
  });
  return wrapper;
}
function configured() {
  const model = newModel(unit);
  model.name = 'Synthetic survey';
  model.channels.public_link.enabled = true;
  model.rules.execution_member_id = 1;
  return model;
}
function transport() {
  let row = null;
  const permissions = {
    edit: true,
    publish: true,
    duplicate: true,
    manage_permissions: true,
  };
  return {
    save: vi.fn(async (_account, payload) => {
      row = {
        id: 1,
        payload: JSON.parse(JSON.stringify(payload)),
        lock_version: (row?.lock_version ?? -1) + 1,
        permissions,
      };
      return { data: row };
    }),
    get: vi.fn(async () => ({ data: JSON.parse(JSON.stringify(row)) })),
    validate: vi.fn(async () => ({ data: { valid: true } })),
    publish: vi.fn(async (_account, _model, _version, key) => {
      row.publication_key = key;
      row.published_version = 1;
      row.lock_version += 1;
      return { data: row };
    }),
    dispatch: vi.fn(),
  };
}

describe('Service Desk survey model six-step modal', () => {
  it('preserves numeric selected days while adding and removing a delivery day', async () => {
    mountEditor();
    wrapper.vm.model = configured();
    wrapper.vm.model.rules.send_window.enabled = true;
    wrapper.vm.model.rules.send_window.days = [1, 2];
    wrapper.vm.go(3);
    await flushPromises();
    await wrapper.findAll('.sv-day-grid button')[3].trigger('click');
    expect(wrapper.vm.model.rules.send_window.days).toEqual([1, 2, 3]);
    await wrapper.findAll('.sv-day-grid button')[1].trigger('click');
    expect(wrapper.vm.model.rules.send_window.days).toEqual([2, 3]);
  });

  it('recovers a partial disabled delivery window with explicit editor defaults', async () => {
    const model = configured();
    model.rules.send_window = { enabled: false };
    mountEditor(transport(), { id: 1, payload: model, lock_version: 0 });
    expect(wrapper.vm.model.rules.send_window.days).toEqual([1, 2, 3, 4, 5]);
    expect(wrapper.vm.model.rules.send_window.enabled).toBe(false);
    expect(wrapper.vm.dirty).toBe(false);
  });

  it('allows a publisher to confirm a saved draft without sending an edit request', async () => {
    const api = transport();
    const stored = await api.save(1, configured());
    const row = {
      ...stored.data,
      permissions: { edit: false, publish: true, manage_permissions: false },
    };
    api.save.mockClear();
    mountEditor(api, row);
    wrapper.vm.confirmPublication = true;
    await wrapper.vm.publish();
    expect(api.save).not.toHaveBeenCalled();
    expect(api.validate).toHaveBeenCalledOnce();
    expect(api.publish).toHaveBeenCalledOnce();
    expect(wrapper.vm.errors).toEqual([]);
    expect(api.dispatch).not.toHaveBeenCalled();
  });

  it('does not persist locally altered fields for a publisher without edit permission', async () => {
    const api = transport();
    const stored = await api.save(1, configured());
    const row = {
      ...stored.data,
      permissions: { edit: false, publish: true, manage_permissions: false },
    };
    api.save.mockClear();
    mountEditor(api, row);
    wrapper.vm.model.name = 'Forbidden local change';
    wrapper.vm.confirmPublication = true;
    await wrapper.vm.publish();
    expect(api.save).not.toHaveBeenCalled();
    expect(api.publish).not.toHaveBeenCalled();
    expect(wrapper.vm.errors.length).toBeGreaterThan(0);
  });
  it('renders six steps in the approved order and suppresses only the NICO presentation', async () => {
    mountEditor();
    await flushPromises();
    expect(wrapper.findAll('.sv-stepper button').map(b => b.text())).toEqual(
      expect.arrayContaining([
        expect.stringContaining('Informações'),
        expect.stringContaining('Perguntas'),
        expect.stringContaining('Canais'),
        expect.stringContaining('Regras de envio'),
        expect.stringContaining('Permissões'),
        expect.stringContaining('Revisão'),
      ])
    );
    expect(surveyModelEditorOpen.value).toBe(true);
    wrapper.unmount();
    wrapper = null;
    expect(surveyModelEditorOpen.value).toBe(false);
  });
  it('blocks advancement without a valid name and preserves the other inputs', async () => {
    mountEditor();
    wrapper.vm.model.description = 'Draft text';
    wrapper.vm.go(1);
    await flushPromises();
    expect(wrapper.vm.step).toBe(0);
    expect(wrapper.vm.errors[0].field).toBe('name');
    expect(wrapper.vm.model.description).toBe('Draft text');
  });
  it('preserves the draft while going back through the steps', async () => {
    mountEditor();
    wrapper.vm.model = configured();
    wrapper.vm.go(5);
    await flushPromises();
    expect(wrapper.vm.step).toBe(5);
    wrapper.vm.go(0);
    await flushPromises();
    expect(wrapper.vm.model.name).toBe('Synthetic survey');
    expect(wrapper.vm.model.channels.public_link.enabled).toBe(true);
  });
  it('saves and verifies through GET without sending or publishing', async () => {
    const api = transport();
    mountEditor(api);
    wrapper.vm.model = configured();
    await wrapper.vm.save();
    expect(api.save).toHaveBeenCalledOnce();
    expect(api.get).toHaveBeenCalledOnce();
    expect(wrapper.vm.dirty).toBe(false);
    expect(api.publish).not.toHaveBeenCalled();
    expect(api.dispatch).not.toHaveBeenCalled();
  });
  it('does not publish without explicit confirmation', async () => {
    const api = transport();
    mountEditor(api);
    wrapper.vm.model = configured();
    await wrapper.vm.publish();
    expect(api.save).not.toHaveBeenCalled();
    expect(api.publish).not.toHaveBeenCalled();
  });
  it('publishes only after validation and confirms the publication key through GET', async () => {
    const api = transport();
    mountEditor(api);
    wrapper.vm.model = configured();
    wrapper.vm.confirmPublication = true;
    await wrapper.vm.publish();
    expect(api.validate).toHaveBeenCalledOnce();
    expect(api.publish).toHaveBeenCalledOnce();
    expect(api.get).toHaveBeenCalledTimes(2);
    expect(wrapper.vm.publicationKey).toBeNull();
    expect(api.dispatch).not.toHaveBeenCalled();
    expect(wrapper.vm.errors).toEqual([]);
  });
  it('keeps inputs on a server field validation error and moves to its step', async () => {
    const api = transport();
    api.save.mockRejectedValue({
      response: {
        status: 422,
        data: {
          errors: [
            { step: 2, field: 'email', message: 'Caixa não autorizada' },
          ],
        },
      },
    });
    mountEditor(api);
    wrapper.vm.model = configured();
    await wrapper.vm.save();
    expect(wrapper.vm.step).toBe(2);
    expect(wrapper.vm.model.name).toBe('Synthetic survey');
    expect(wrapper.vm.dirty).toBe(true);
    expect(wrapper.vm.operationUnknown).toBe(false);
  });
  it('does not repeat a lost write before explicit reconciliation', async () => {
    const api = transport();
    api.save.mockRejectedValue(new Error('network lost'));
    mountEditor(api);
    wrapper.vm.model = configured();
    await wrapper.vm.save();
    await wrapper.vm.save();
    expect(api.save).toHaveBeenCalledOnce();
    expect(wrapper.vm.operationUnknown).toBe(true);
  });
  it('asks before discarding unsaved changes and cancel itself writes nothing', async () => {
    const api = transport();
    mountEditor(api);
    wrapper.vm.model.name = 'Unsaved';
    wrapper.vm.close();
    await flushPromises();
    expect(wrapper.vm.leavePrompt).toBe(true);
    expect(wrapper.emitted('close')).toBeUndefined();
    wrapper.vm.discard();
    expect(wrapper.emitted('close')).toHaveLength(1);
    expect(api.save).not.toHaveBeenCalled();
  });
});
