import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { computed, ref } from 'vue';
import { enableAutoUnmount, mount } from '@vue/test-utils';
import EndingAutomationEditor from './EndingAutomationEditor.vue';

const state = vi.hoisted(() => ({ editor: null }));
vi.mock('../composables/useEndingAutomationEditor', () => ({
  useEndingAutomationEditor: () => state.editor,
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
enableAutoUnmount(afterEach);

const create = () =>
  mount(EndingAutomationEditor, {
    props: { accountId: '1' },
    global: {
      stubs: {
        AcwRuleTarget: true,
        ConfigurationRevisionConflict: true,
        EndingProjectTaskConfiguration: true,
        EndingCrmConfiguration: true,
        EndingServiceDeskConfiguration: true,
        EndingRuleActivation: true,
      },
    },
  });

beforeEach(() => {
  const draft = ref({
    code: 'SYNTHETIC_MANUAL',
    name: 'SYNTHETIC manual rule',
    reason_code: 'SYNTHETIC_REASON',
    queue_id: 12,
    timing: 'call_end',
    execution_mode: 'agent_confirmation',
    active: true,
    conditions: { outcome_codes: [] },
    actions: [
      { kind: 'project_task', parameters: { title: 'SYNTHETIC task' } },
    ],
  });
  const initial = JSON.stringify(draft.value);
  state.editor = {
    items: ref([]),
    meta: ref({ page: 1, pages: 1, total: 1 }),
    q: ref(''),
    status: ref('all'),
    page: ref(1),
    draft,
    source: ref(null),
    persisted: ref(true),
    reasons: ref([{ code: 'SYNTHETIC_REASON', name: 'SYNTHETIC reason' }]),
    crmOptions: ref({ configuration_available: false, activity_types: [] }),
    serviceDeskOptions: ref({ configuration_available: false }),
    destinationPresentations: ref({}),
    loading: ref(false),
    saving: ref(false),
    sourceLoading: ref(false),
    error: ref(''),
    reviewed: ref(true),
    saved: ref(false),
    dirty: computed(() => JSON.stringify(draft.value) !== initial),
    canSave: ref(false),
    activationRevision: ref('synthetic-revision'),
    revision: {
      state: { conflict: false },
      reviewed: () => false,
      reload: vi.fn(),
    },
    save: vi.fn(),
    deny: vi.fn(),
    discard: vi.fn(),
    selectQueue: vi.fn(),
    reviewConflict: vi.fn(),
  };
});

// Component interaction checks, not substitutes for native authority or Chrome.
describe('explicit manual automation version choice', () => {
  it('preserves a historical manual rule on opening without preparing or saving it', () => {
    const wrapper = create();
    expect(state.editor.draft.value.destination_schema_version).toBeUndefined();
    expect(wrapper.find('[data-enable-ending-manual-flow]').exists()).toBe(
      true
    );
    expect(
      wrapper.findComponent({ name: 'EndingRuleActivation' }).exists()
    ).toBe(false);
    expect(state.editor.save).not.toHaveBeenCalled();
    expect(state.editor.reviewed.value).toBe(true);
  });

  it('requires an explicit version choice and invalidates the old review while retaining all destinations', async () => {
    const wrapper = create();
    const actions = JSON.stringify(state.editor.draft.value.actions);
    await wrapper.get('[data-enable-ending-manual-flow]').trigger('click');
    expect(state.editor.draft.value.destination_schema_version).toBe(2);
    expect(JSON.stringify(state.editor.draft.value.actions)).toBe(actions);
    expect(state.editor.reviewed.value).toBe(false);
    expect(state.editor.dirty.value).toBe(true);
    expect(state.editor.save).not.toHaveBeenCalled();
    expect(
      wrapper.find('[data-ending-manual-activation-pending]').exists()
    ).toBe(false);
    expect(
      wrapper.findComponent({ name: 'EndingRuleActivation' }).exists()
    ).toBe(false);
  });

  it('chooses the typed flow only when the user selects individual confirmation', async () => {
    state.editor.draft.value.execution_mode = 'automatic';
    const wrapper = create();
    expect(state.editor.draft.value.destination_schema_version).toBeUndefined();
    await wrapper
      .get('[data-ending-execution-mode]')
      .setValue('agent_confirmation');
    expect(state.editor.draft.value.destination_schema_version).toBe(2);
    expect(state.editor.reviewed.value).toBe(false);
    expect(state.editor.save).not.toHaveBeenCalled();
  });

  it('retains the typed destination schema when switching back to automatic and requires a new review', async () => {
    state.editor.draft.value.destination_schema_version = 2;
    const wrapper = create();
    await wrapper.get('[data-ending-execution-mode]').setValue('automatic');
    expect(state.editor.draft.value.destination_schema_version).toBe(2);
    expect(state.editor.reviewed.value).toBe(false);
    expect(state.editor.save).not.toHaveBeenCalled();
  });

  it('disables the legacy version choice while a save is in flight', async () => {
    state.editor.saving.value = true;
    const wrapper = create();
    const button = wrapper.get('[data-enable-ending-manual-flow]');
    expect(button.element.disabled).toBe(true);
    await button.trigger('click');
    expect(state.editor.draft.value.destination_schema_version).toBeUndefined();
    expect(state.editor.reviewed.value).toBe(true);
    expect(state.editor.save).not.toHaveBeenCalled();
  });
});

describe('native Service Desk rule configuration', () => {
  it('keeps the destination unavailable without the current authorized source and native context', () => {
    const wrapper = create();
    expect(
      wrapper.get('[data-ending-configure-destination="service_desk"]').element
        .disabled
    ).toBe(true);
    expect(
      wrapper.findComponent({ name: 'EndingServiceDeskConfiguration' }).exists()
    ).toBe(false);
    expect(state.editor.save).not.toHaveBeenCalled();
  });

  it('applies separately reviewed parameters while preserving the existing Project action and deferring persistence', async () => {
    state.editor.source.value = { scope_revision: 'a'.repeat(64) };
    state.editor.serviceDeskOptions.value = {
      configuration_available: true,
      unit: { id: '11', name: 'SYNTHETIC mapped' },
    };
    const wrapper = create();
    const previous = JSON.stringify(state.editor.draft.value.actions);
    await wrapper
      .get('[data-ending-configure-destination="service_desk"]')
      .trigger('click');
    const panel = wrapper.findComponent({
      name: 'EndingServiceDeskConfiguration',
    });
    expect(panel.exists()).toBe(true);
    const parameters = {
      unit_id: '11',
      service_id: null,
      attributes: {
        title: 'SYNTHETIC reviewed',
        description: 'SYNTHETIC reviewed',
      },
    };
    panel.vm.$emit('save', parameters);
    await wrapper.vm.$nextTick();
    expect(
      JSON.stringify(
        state.editor.draft.value.actions.filter(
          row => row.kind === 'project_task'
        )
      )
    ).toBe(previous);
    expect(
      state.editor.draft.value.actions.find(row => row.kind === 'service_desk')
        .parameters
    ).toEqual(parameters);
    expect(state.editor.draft.value.destination_schema_version).toBe(2);
    expect(state.editor.save).not.toHaveBeenCalled();
  });

  it('preserves all parameters on cancel and removes only the explicitly selected destination', async () => {
    state.editor.source.value = { scope_revision: 'a'.repeat(64) };
    state.editor.serviceDeskOptions.value = {
      configuration_available: true,
      unit: { id: '11', name: 'SYNTHETIC mapped' },
    };
    state.editor.draft.value.actions.push({
      kind: 'service_desk',
      parameters: { unit_id: '11' },
    });
    const previous = JSON.stringify(state.editor.draft.value.actions);
    const wrapper = create();
    await wrapper
      .get('[data-ending-configure-destination="service_desk"]')
      .trigger('click');
    wrapper
      .findComponent({ name: 'EndingServiceDeskConfiguration' })
      .vm.$emit('cancel');
    await wrapper.vm.$nextTick();
    expect(JSON.stringify(state.editor.draft.value.actions)).toBe(previous);
    await wrapper
      .get('[data-ending-configure-destination="service_desk"]')
      .trigger('click');
    wrapper
      .findComponent({ name: 'EndingServiceDeskConfiguration' })
      .vm.$emit('remove');
    await wrapper.vm.$nextTick();
    expect(state.editor.draft.value.actions.map(row => row.kind)).toEqual([
      'project_task',
    ]);
    expect(state.editor.save).not.toHaveBeenCalled();
  });
});
