import { computed, nextTick, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { validCalendar } from '../automationStudio/calendarRules';
import Drafts from 'dashboard/api/serviceDeskAutomationDrafts';
import API from 'dashboard/api/serviceDeskCockpit';
import { useServiceDesk } from './useServiceDesk';
import { communicationLabels } from '../helpers/communicationLabels';
import { v2Labels } from '../helpers/v2Labels';

export function useNotificationPolicy(props, emit = () => {}, options = {}) {
  const includeMetadata = options.includeMetadata === true;
  const step = ref('general');
  const publicationUncertain = ref(false);
  const attemptedPolicy = ref(null);
  const { t } = useI18n();
  const session = useServiceDesk();
  const labels = computed(() => communicationLabels(t));
  const values = computed(() => v2Labels(t));
  const allowed = computed(
    () =>
      session.state.status === 'ready' &&
      session.state.context?.capabilities?.notifications?.manage === true
  );
  const unitId = ref('');
  const operatorId = ref('');
  const policies = ref([]);
  const inboxes = ref([]);
  const loading = ref(false);
  const previewed = ref(false);
  const draftFeedback = ref('');
  const draftVersion = ref(-1);
  const events = ref([]);
  const eventType = ref('customer_interaction');
  const channel = ref('email');
  const ticketTypeId = ref('');
  const serviceId = ref('');
  const template = ref('');
  const templateVersion = ref('');
  const displayName = ref('');
  const description = ref('');
  const inboxId = ref('');
  const enabled = ref(false);
  const controls = ref({
    conditions: { operator: 'all', items: [] },
    channel_order: ['email'],
    multichannel_mode: 'first_available',
    additional_contact_ids: [],
    internal_copy_member_ids: [],
    window: { enabled: false },
    outside_window: 'defer',
    max_attempts: 1,
    backoff_minutes: 10,
  });
  const channelConfigurations = ref({});
  const configurationFor = () => ({
    inbox_id: inboxId.value || null,
    template: template.value,
    template_version: templateVersion.value,
  });
  watch(
    channel,
    (next, old) => {
      if (!includeMetadata) return;
      channelConfigurations.value[old] = configurationFor();
      const cfg = channelConfigurations.value[next] || {};
      inboxId.value = cfg.inbox_id || '';
      template.value = cfg.template || '';
      templateVersion.value = cfg.template_version || '';
    },
    { flush: 'sync' }
  );
  const confirmed = ref(false);
  const busy = ref(false);
  const locked = computed(() => busy.value || publicationUncertain.value);
  watch(locked, value => emit('busyChange', value));
  const feedback = ref(null);
  let generation = 0;
  let controller;
  const currentPolicies = computed(() => {
    const seen = new Set();
    return policies.value.filter(row => {
      const key = JSON.stringify([
        row.event_type,
        row.channel,
        row.ticket_type_id || null,
        row.service_id || null,
      ]);
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    });
  });
  const permittedInboxes = computed(() =>
    inboxes.value.filter(row => row.channel === channel.value)
  );
  const tokens = [
    'body',
    'number',
    'title',
    'status',
    'priority',
    'queue',
    'assignee',
    'task_title',
    'task_status',
    'customer_name',
    'company_name',
    'operator_company',
  ];
  const invalidTokens = computed(() =>
    [...template.value.matchAll(/\{\{(.*?)\}\}/g)]
      .map(match => match[1])
      .filter(key => !tokens.includes(key))
  );
  const examplePreview = computed(() =>
    template.value.replace(/\{\{(.*?)\}\}/g, (match, key) =>
      tokens.includes(key)
        ? t(`JRC_SERVICE_DESK.REDESIGN_AUTOMATIONS.examples.${key}`)
        : match
    )
  );
  const draftKey = () =>
    `jrc:service-desk:policy-draft:v1:${session.state.context.account_id}:${session.state.context.user_id}:${unitId.value}`;
  const latest = computed(() =>
    policies.value.find(
      row =>
        row.event_type === eventType.value &&
        row.channel === channel.value &&
        (row.ticket_type_id || '') === ticketTypeId.value &&
        (row.service_id || '') === serviceId.value
    )
  );
  const scopeMatches = (row, policy) =>
    row.event_type === policy.event_type &&
    (row.ticket_type_id || null) === policy.ticket_type_id &&
    (row.service_id || null) === policy.service_id;
  const sameJSON = (a, b) => {
    if (a === b) return true;
    if (!a || !b || typeof a !== 'object' || typeof b !== 'object')
      return false;
    const keys = Object.keys(a).sort();
    return (
      JSON.stringify(keys) === JSON.stringify(Object.keys(b).sort()) &&
      keys.every(key => sameJSON(a[key], b[key]))
    );
  };
  const verifiedPolicy = (rows, policy) => {
    const channels = includeMetadata
      ? policy.settings.channel_order
      : [policy.channel];
    return [...channels, ...(policy.retired_channels || [])].every(key => {
      const row = rows.find(
        item => scopeMatches(item, policy) && item.channel === key
      );
      const retired = policy.retired_channels?.includes(key);
      const cfg = includeMetadata ? policy.channel_configurations[key] : policy;
      const version = includeMetadata
        ? policy.expected_versions[key]
        : policy.expected_version;
      return (
        row?.version === version + 1 &&
        (retired
          ? row.enabled === false
          : row.enabled === policy.enabled &&
            row.template === cfg.template &&
            row.template_version === cfg.template_version &&
            row.inbox_id === cfg.inbox_id &&
            (!includeMetadata ||
              (row.display_name === policy.display_name &&
                row.description === policy.description &&
                sameJSON(row.settings, policy.settings))))
      );
    });
  };
  const validConfigurations = computed(
    () =>
      !includeMetadata ||
      ((!controls.value.window.enabled ||
        validCalendar(controls.value.window)) &&
        controls.value.channel_order.every(key => {
          const cfg =
            key === channel.value
              ? configurationFor()
              : channelConfigurations.value[key];
          return (
            cfg &&
            (key !== 'whatsapp' ||
              !controls.value.whatsapp_template ||
              (String(controls.value.whatsapp_template.inbox_id) ===
                String(cfg.inbox_id) &&
                inboxes.value
                  .find(row => row.id === cfg.inbox_id)
                  ?.whatsapp_templates?.some(
                    row =>
                      row.fingerprint ===
                      controls.value.whatsapp_template.fingerprint
                  ) &&
                Object.values(
                  controls.value.whatsapp_template.params.processed_params.body
                ).every(value => typeof value === 'string' && value.trim()))) &&
            typeof cfg.template === 'string' &&
            !!cfg.template.trim() &&
            typeof cfg.template_version === 'string' &&
            !!cfg.template_version.trim() &&
            ![...cfg.template.matchAll(/\{\{(.*?)\}\}/g)].some(
              match => !tokens.includes(match[1])
            ) &&
            (!enabled.value ||
              inboxes.value.some(
                row => row.channel === key && row.id === cfg.inbox_id
              ))
          );
        }))
  );
  const retiredChannels = computed(() =>
    currentPolicies.value
      .filter(
        row =>
          row.enabled &&
          scopeMatches(row, {
            event_type: eventType.value,
            ticket_type_id: ticketTypeId.value || null,
            service_id: serviceId.value || null,
          }) &&
          !controls.value.channel_order.includes(row.channel)
      )
      .map(row => row.channel)
  );
  const clear = () => {
    controls.value = {
      conditions: { operator: 'all', items: [] },
      channel_order: ['email'],
      multichannel_mode: 'first_available',
      additional_contact_ids: [],
      internal_copy_member_ids: [],
      window: { enabled: false },
      outside_window: 'defer',
      max_attempts: 1,
      backoff_minutes: 10,
    };
    channelConfigurations.value = {};
    draftVersion.value = -1;
    enabled.value = false;
    confirmed.value = false;
    inboxId.value = '';
    template.value = '';
    templateVersion.value = '';
    displayName.value = '';
    description.value = '';
    previewed.value = false;
  };
  const active = (context, turn) =>
    allowed.value && context === session.state.context && turn === generation;
  const decode = (payload, context, unit) => {
    if (
      payload.contract_version !== 1 ||
      payload.account_id !== context.account_id ||
      payload.unit_id !== unit ||
      !Array.isArray(payload.policies) ||
      !Array.isArray(payload.event_types)
    )
      throw new Error('Invalid policy scope');
    return payload;
  };
  const load = async () => {
    generation += 1;
    controller?.abort();
    policies.value = [];
    events.value = [];
    inboxes.value = [];
    feedback.value = null;
    draftFeedback.value = '';
    loading.value = false;
    if (!allowed.value || !unitId.value) return;
    controller = new AbortController();
    loading.value = true;
    const context = session.state.context;
    const turn = generation;
    try {
      const result = decode(
        await API.policies(context.account_id, unitId.value, controller.signal),
        context,
        unitId.value
      );
      if (!active(context, turn)) return;
      if (publicationUncertain.value && attemptedPolicy.value) {
        const wanted = attemptedPolicy.value;
        const saved = verifiedPolicy(result.policies, wanted);
        if (saved) {
          feedback.value = 'saved';
          attemptedPolicy.value = null;
        } else feedback.value = 'error';
      }
      publicationUncertain.value = false;
      policies.value = result.policies;
      events.value = result.event_types;
      inboxes.value = (result.inboxes || []).filter(
        row =>
          typeof row.id === 'string' &&
          typeof row.name === 'string' &&
          ['email', 'whatsapp'].includes(row.channel)
      );
    } catch (error) {
      if (active(context, turn)) feedback.value = 'unavailable';
    } finally {
      if (active(context, turn)) loading.value = false;
    }
  };
  watch(
    [unitId, () => session.state.context, () => session.state.status],
    () => {
      attemptedPolicy.value = null;
      publicationUncertain.value = false;
      clear();
      load();
    }
  );
  watch(unitId, () => {
    ticketTypeId.value = '';
    serviceId.value =
      props.initialUnitId === unitId.value ? props.initialServiceId : '';
  });
  watch(
    [() => props.initialUnitId, () => session.state.context],
    () => {
      if (!props.initialUnitId || busy.value) return;
      if (
        session.state.context?.units.some(row => row.id === props.initialUnitId)
      )
        unitId.value = props.initialUnitId;
    },
    { immediate: true }
  );
  watch([latest, eventType, channel, ticketTypeId, serviceId], () => {
    if (includeMetadata) {
      confirmed.value = false;
      previewed.value = false;
      if (!permittedInboxes.value.some(row => row.id === inboxId.value))
        inboxId.value = '';
      return;
    }
    clear();
    const row = latest.value;
    if (row) {
      enabled.value = row.enabled;
      inboxId.value = row.inbox_id || '';
      template.value = row.template;
      templateVersion.value = row.template_version;
      displayName.value = row.display_name || '';
      description.value = row.description || '';
    }
  });
  watch([eventType, channel, ticketTypeId, serviceId], () => {
    feedback.value = null;
    draftFeedback.value = '';
  });
  watch(
    [template, templateVersion, inboxId, enabled, displayName, description],
    () => {
      confirmed.value = false;
      previewed.value = false;
    }
  );
  const selectPolicy = row => {
    if (locked.value) return;
    step.value = 'general';
    eventType.value = row.event_type;
    channel.value = row.channel;
    ticketTypeId.value = row.ticket_type_id || '';
    serviceId.value = row.service_id || '';
    if (includeMetadata) {
      if (row.settings && Object.keys(row.settings).length)
        controls.value = JSON.parse(JSON.stringify(row.settings));
      else controls.value = { ...controls.value, channel_order: [row.channel] };
      channelConfigurations.value = Object.fromEntries(
        currentPolicies.value
          .filter(
            item =>
              item.event_type === row.event_type &&
              (item.ticket_type_id || '') === (row.ticket_type_id || '') &&
              (item.service_id || '') === (row.service_id || '')
          )
          .map(item => [
            item.channel,
            {
              inbox_id: item.inbox_id,
              template: item.template,
              template_version: item.template_version,
            },
          ])
      );
      displayName.value = row.display_name || '';
      description.value = row.description || '';
      template.value = row.template || '';
      templateVersion.value = row.template_version || '';
      inboxId.value = row.inbox_id || '';
      enabled.value = row.enabled === true;
      confirmed.value = false;
      previewed.value = false;
    }
  };
  const saveDraft = async () => {
    try {
      const savedDraft = await Drafts.save(
        session.state.context.account_id,
        unitId.value,
        'notification',
        'editor',
        {
          event_type: eventType.value,
          channel: channel.value,
          ticket_type_id: ticketTypeId.value,
          service_id: serviceId.value,
          template: template.value,
          template_version: templateVersion.value,
          display_name: displayName.value,
          description: description.value,
          inbox_id: inboxId.value,
          enabled: enabled.value,
          base_version: latest.value?.version || 0,
          controls: controls.value,
          channel_configurations: {
            ...channelConfigurations.value,
            [channel.value]: configurationFor(),
          },
        },
        draftVersion.value
      );
      draftVersion.value = savedDraft.lock_version;
      draftFeedback.value = 'draft_saved';
    } catch {
      draftFeedback.value = 'draft_unavailable';
    }
  };
  const restoreDraft = async () => {
    try {
      const restored = await Drafts.read(
        session.state.context.account_id,
        unitId.value,
        'notification',
        'editor'
      );
      const draft = restored.payload;
      draftVersion.value = restored.lock_version;
      if (
        !draft ||
        !events.value.includes(draft.event_type) ||
        !['email', 'whatsapp'].includes(draft.channel) ||
        typeof draft.template !== 'string' ||
        typeof draft.template_version !== 'string' ||
        typeof draft.enabled !== 'boolean'
      )
        throw new TypeError('Invalid draft');
      selectPolicy(draft);
      await nextTick();
      template.value = draft.template;
      templateVersion.value = draft.template_version;
      displayName.value =
        typeof draft.display_name === 'string' ? draft.display_name : '';
      description.value =
        typeof draft.description === 'string' ? draft.description : '';
      inboxId.value = permittedInboxes.value.some(
        row => row.id === draft.inbox_id
      )
        ? draft.inbox_id
        : '';
      enabled.value = draft.enabled;
      if (draft.controls) controls.value = draft.controls;
      channelConfigurations.value = draft.channel_configurations || {};
      confirmed.value = false;
      draftFeedback.value =
        draft.base_version === (latest.value?.version || 0)
          ? 'draft_restored'
          : 'draft_stale';
    } catch {
      draftFeedback.value = 'draft_unavailable';
    }
  };
  const publish = async () => {
    if (
      !allowed.value ||
      !confirmed.value ||
      busy.value ||
      publicationUncertain.value ||
      step.value !== 'review' ||
      !unitId.value ||
      !events.value.includes(eventType.value) ||
      !validConfigurations.value ||
      !template.value.trim() ||
      !templateVersion.value.trim() ||
      invalidTokens.value.length ||
      (enabled.value &&
        !permittedInboxes.value.some(row => row.id === inboxId.value))
    )
      return;
    const context = session.state.context;
    const turn = generation;
    const unit = unitId.value;
    const policy = {
      event_type: eventType.value,
      channel: channel.value,
      template: template.value,
      template_version: templateVersion.value,
      ...(includeMetadata
        ? {
            display_name: displayName.value,
            description: description.value,
            settings: {
              ...controls.value,
              additional_contact_ids:
                controls.value.additional_contact_ids.map(Number),
              internal_copy_member_ids:
                controls.value.internal_copy_member_ids.map(Number),
            },
            channel_configurations: Object.fromEntries(
              controls.value.channel_order.map(key => [
                key,
                key === channel.value
                  ? configurationFor()
                  : channelConfigurations.value[key] || {},
              ])
            ),
            retired_channels: retiredChannels.value,
            expected_versions: Object.fromEntries(
              [...controls.value.channel_order, ...retiredChannels.value].map(
                key => [
                  key,
                  currentPolicies.value.find(
                    row =>
                      row.event_type === eventType.value &&
                      row.channel === key &&
                      (row.ticket_type_id || '') === ticketTypeId.value &&
                      (row.service_id || '') === serviceId.value
                  )?.version || 0,
                ]
              )
            ),
          }
        : {}),
      inbox_id: inboxId.value || null,
      enabled: enabled.value,
      confirmed: true,
      expected_version: latest.value?.version || 0,
      ticket_type_id: ticketTypeId.value || null,
      service_id: serviceId.value || null,
    };
    attemptedPolicy.value = { ...policy };
    busy.value = true;
    try {
      const ack = await API.publishPolicy(
        context.account_id,
        unit,
        policy,
        controller.signal
      );
      if (!active(context, turn)) return;
      const result = decode(
        await API.policies(context.account_id, unit, controller.signal),
        context,
        unit
      );
      if (!active(context, turn)) return;
      if (
        !ack.applied ||
        ack.account_id !== context.account_id ||
        !verifiedPolicy(result.policies, policy)
      )
        throw new Error('Unverified policy');
      policies.value = result.policies;
      feedback.value = 'saved';
      attemptedPolicy.value = null;
      confirmed.value = false;
    } catch (error) {
      if (active(context, turn)) {
        if ([401, 403].includes(error.response?.status))
          feedback.value = 'denied';
        else
          feedback.value =
            error.response?.status === 422 ? 'error' : 'uncertain';
        publicationUncertain.value = feedback.value === 'uncertain';
        confirmed.value = false;
      }
    } finally {
      busy.value = false;
    }
  };
  onBeforeUnmount(() => {
    emit('busyChange', false);
    generation += 1;
    controller?.abort();
    policies.value = [];
    clear();
  });
  return {
    t,
    controls,
    channelConfigurations,
    configurationFor,
    validConfigurations,
    step,
    publicationUncertain,
    attemptedPolicy,
    session,
    labels,
    values,
    allowed,
    unitId,
    operatorId,
    policies,
    inboxes,
    loading,
    previewed,
    draftFeedback,
    events,
    eventType,
    channel,
    ticketTypeId,
    serviceId,
    template,
    templateVersion,
    displayName,
    description,
    inboxId,
    enabled,
    confirmed,
    busy,
    locked,
    feedback,
    currentPolicies,
    permittedInboxes,
    tokens,
    invalidTokens,
    examplePreview,
    draftKey,
    latest,
    clear,
    active,
    decode,
    load,
    selectPolicy,
    saveDraft,
    restoreDraft,
    publish,
  };
}
