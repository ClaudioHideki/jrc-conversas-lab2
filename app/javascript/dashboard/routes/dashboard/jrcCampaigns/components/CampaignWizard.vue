<script setup>
import CampaignFilters from 'dashboard/routes/dashboard/jrcCustomers/components/CampaignFilters.vue';
import { useCustomerMaster } from 'dashboard/routes/dashboard/jrcCustomers/useCustomerMaster';
const props = defineProps({
  campaign: { type: Object, default: null },
  metadata: { type: Object, required: true },
});
const emit = defineEmits(['close', 'saved']);
const { enabled: hasCustomerMaster } = useCustomerMaster();
import {
  computed,
  onBeforeUnmount,
  onMounted,
  reactive,
  ref,
  watch,
} from 'vue';
import { useI18n } from 'vue-i18n';
import JrcCampaignsAPI from 'dashboard/api/jrcCampaigns';
import { useAlert } from 'dashboard/composables';

const { t } = useI18n();
const stepIndex = ref(0);
const saving = ref(false);
const uploadingStep = ref(null);
const previewingAudience = ref(false);
const audiencePreview = ref({
  found_count: null,
  estimated_recipients: null,
  without_whatsapp_count: 0,
  blacklisted_count: 0,
  blocked_count: 0,
  duplicate_count: 0,
  sample: [],
});
const activeMessageIndex = ref(0);
const showAudienceSample = ref(false);
const testPhone = ref('');
const testSending = ref(false);
let audienceTimer;

const defaultMessage = () => ({
  id: null,
  position: 0,
  kind: 'template',
  body: '',
  media_url: '',
  file_name: '',
  template_name: '',
  template_namespace: '',
  template_language: 'pt_BR',
  template_params: {},
  templateParamsText: '{}',
  variableMappings: {},
  variableValues: {},
  inbox_overrides: {},
  delay_after_seconds: 0,
  only_if_no_reply: false,
  follow_up_after_hours: null,
  advancedOpen: false,
});

const form = reactive({
  name: '',
  audience_type: 'all_contacts',
  audience_config: {
    label_ids: [],
    inbox_ids: [],
    pipeline_id: null,
    stage_ids: [],
    sanitized_list_id: null,
    customer_filters: {},
  },
  inboxLinks: [],
  rotation_mode: 'round_robin',
  delay_min_seconds: 5,
  delay_max_seconds: 20,
  sending_window: { start: '08:00', end: '18:00', days: [1, 2, 3, 4, 5] },
  conversation_mode: 'reply_only',
  trigger_type: 'manual',
  scheduled_at: '',
  recurrence_config: { type: 'none', interval_days: 7 },
  follow_up_config: { on_reply_label_id: null, on_reply_stage_id: null },
  steps: [defaultMessage()],
});

const selectedPipeline = computed(() =>
  props.metadata.pipelines?.find(
    item => Number(item.id) === Number(form.audience_config.pipeline_id)
  )
);
const selectedInboxIds = computed(() =>
  form.inboxLinks.map(item => Number(item.inbox_id))
);
const selectedSendingInboxes = computed(() =>
  (props.metadata.inboxes || []).filter(inbox =>
    selectedInboxIds.value.includes(Number(inbox.id))
  )
);
const templates = computed(() => {
  const uniqueTemplates = new Map();
  selectedSendingInboxes.value.forEach(inbox => {
    (inbox.templates || []).forEach(template => {
      uniqueTemplates.set(`${template.name}::${template.language}`, template);
    });
  });
  return [...uniqueTemplates.values()];
});
const allStages = computed(() =>
  (props.metadata.pipelines || []).flatMap(pipeline => pipeline.stages || [])
);
const wizardSteps = computed(() => [
  {
    label: t('JRC_CAMPAIGNS.WIZARD.STEP_AUDIENCE'),
    icon: 'i-lucide-users-round',
  },
  {
    label: t('JRC_CAMPAIGNS.WIZARD.STEP_CONFIG_SHORT'),
    icon: 'i-lucide-sliders-horizontal',
  },
  {
    label: t('JRC_CAMPAIGNS.WIZARD.STEP_MESSAGES_SHORT'),
    icon: 'i-lucide-messages-square',
  },
  {
    label: t('JRC_CAMPAIGNS.WIZARD.STEP_REVIEW_SHORT'),
    icon: 'i-lucide-clipboard-check',
  },
]);
const sourceCards = computed(() => [
  {
    key: 'all_contacts',
    label: t('JRC_CAMPAIGNS.WIZARD.SOURCE_ALL'),
    description: t('JRC_CAMPAIGNS.WIZARD.SOURCE_ALL_HELP'),
    icon: 'i-lucide-users-round',
  },
  {
    key: 'label',
    label: t('JRC_CAMPAIGNS.WIZARD.SOURCE_LABEL'),
    description: t('JRC_CAMPAIGNS.WIZARD.SOURCE_LABEL_HELP'),
    icon: 'i-lucide-tags',
  },
  {
    key: 'inbox',
    label: t('JRC_CAMPAIGNS.WIZARD.SOURCE_INBOX'),
    description: t('JRC_CAMPAIGNS.WIZARD.SOURCE_INBOX_HELP'),
    icon: 'i-lucide-inbox',
  },
  {
    key: 'crm_stage',
    label: t('JRC_CAMPAIGNS.WIZARD.SOURCE_CRM'),
    description: t('JRC_CAMPAIGNS.WIZARD.SOURCE_CRM_HELP'),
    icon: 'i-lucide-kanban-square',
  },
  {
    key: 'sanitized_list',
    label: t('JRC_CAMPAIGNS.WIZARD.SOURCE_SANITIZED'),
    description: t('JRC_CAMPAIGNS.WIZARD.SOURCE_SANITIZED_HELP'),
    icon: 'i-lucide-list-checks',
  },
]);
const rotationModes = computed(() => [
  {
    key: 'round_robin',
    label: t('JRC_CAMPAIGNS.WIZARD.ROUND_ROBIN'),
    description: t('JRC_CAMPAIGNS.WIZARD.ROUND_ROBIN_HELP'),
  },
  {
    key: 'least_used',
    label: t('JRC_CAMPAIGNS.WIZARD.LEAST_USED'),
    description: t('JRC_CAMPAIGNS.WIZARD.LEAST_USED_HELP'),
  },
  {
    key: 'priority',
    label: t('JRC_CAMPAIGNS.WIZARD.PRIORITY'),
    description: t('JRC_CAMPAIGNS.WIZARD.PRIORITY_HELP'),
  },
]);
const mappingOptions = computed(() => [
  { value: '', label: t('JRC_CAMPAIGNS.WIZARD.VARIABLE_SELECT') },
  { value: '{{nome}}', label: t('JRC_CAMPAIGNS.WIZARD.VARIABLE_CONTACT_NAME') },
  {
    value: '{{telefone}}',
    label: t('JRC_CAMPAIGNS.WIZARD.VARIABLE_CONTACT_PHONE'),
  },
  {
    value: '{{email}}',
    label: t('JRC_CAMPAIGNS.WIZARD.VARIABLE_CONTACT_EMAIL'),
  },
  {
    value: '{{account.name}}',
    label: t('JRC_CAMPAIGNS.WIZARD.VARIABLE_ACCOUNT_NAME'),
  },
  {
    value: '{{inbox.name}}',
    label: t('JRC_CAMPAIGNS.WIZARD.VARIABLE_INBOX_NAME'),
  },
  { value: '__custom__', label: t('JRC_CAMPAIGNS.WIZARD.VARIABLE_CUSTOM') },
]);

const formatNumber = value =>
  new Intl.NumberFormat(undefined).format(Number(value || 0));
const variableToken = variable => `{{${variable}}}`;
const formatDuration = seconds => {
  if (seconds === null || Number.isNaN(seconds))
    return t('JRC_CAMPAIGNS.WIZARD.CALCULATING');
  if (seconds < 60) return t('JRC_CAMPAIGNS.WIZARD.LESS_THAN_MINUTE');
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.ceil((seconds % 3600) / 60);
  if (!hours) return t('JRC_CAMPAIGNS.WIZARD.DURATION_MINUTES', { minutes });
  return t('JRC_CAMPAIGNS.WIZARD.DURATION_HOURS', { hours, minutes });
};
const templateForMessage = message =>
  templates.value.find(
    template =>
      template.name === message.template_name &&
      template.language === message.template_language
  );
const templateBody = template => {
  const component = (template?.components || []).find(
    item => item.type?.toLowerCase() === 'body'
  );
  return component?.text || '';
};
const variablesForMessage = message => {
  if (message.kind !== 'template') return [];
  const matches = templateBody(templateForMessage(message)).matchAll(
    /\{\{\s*([^{}]+?)\s*\}\}/g
  );
  return [...new Set([...matches].map(match => match[1]))];
};
const inboxHealth = inbox => {
  const status = inbox.health_status?.toUpperCase();
  if (['CONNECTED', 'APPROVED', 'ACTIVE', 'VERIFIED'].includes(status))
    return {
      state: 'connected',
      label: t('JRC_CAMPAIGNS.WIZARD.INBOX_CONNECTED'),
      className: 'bg-n-teal-3 text-n-teal-11',
    };
  if (
    inbox.health_error ||
    ['DISCONNECTED', 'RESTRICTED', 'BANNED', 'REJECTED'].includes(status)
  )
    return {
      state: 'error',
      label: t('JRC_CAMPAIGNS.WIZARD.INBOX_PROBLEM'),
      className: 'bg-n-ruby-3 text-n-ruby-11',
    };
  return {
    state: 'configured',
    label: t('JRC_CAMPAIGNS.WIZARD.INBOX_CONFIGURED'),
    className: 'bg-n-blue-3 text-n-blue-11',
  };
};

const sourceValid = computed(() => {
  if (form.audience_type === 'label')
    return form.audience_config.label_ids.length > 0;
  if (form.audience_type === 'inbox')
    return form.audience_config.inbox_ids.length > 0;
  if (form.audience_type === 'crm_stage')
    return form.audience_config.stage_ids.length > 0;
  if (form.audience_type === 'sanitized_list')
    return Boolean(form.audience_config.sanitized_list_id);
  return true;
});
const configValid = computed(
  () =>
    form.inboxLinks.length > 0 &&
    form.sending_window.days.length > 0 &&
    Number(form.delay_min_seconds) >= 0 &&
    Number(form.delay_max_seconds) >= Number(form.delay_min_seconds) &&
    (form.trigger_type !== 'scheduled' || Boolean(form.scheduled_at)) &&
    (form.recurrence_config.type !== 'custom' ||
      Number(form.recurrence_config.interval_days) > 0)
);
const messageValid = message => {
  if (message.kind === 'text') return Boolean(message.body.trim());
  if (message.kind === 'template') {
    return (
      Boolean(message.template_name && message.template_language) &&
      variablesForMessage(message).every(variable => {
        const mapping = message.variableMappings[variable];
        return (
          Boolean(mapping) &&
          (mapping !== '__custom__' ||
            Boolean(message.variableValues[variable]?.trim()))
        );
      })
    );
  }
  return Boolean(message.media_url);
};
const messagesValid = computed(
  () => form.steps.length > 0 && form.steps.every(messageValid)
);
const currentStepValid = computed(() => {
  if (stepIndex.value === 0)
    return Boolean(form.name.trim()) && sourceValid.value;
  if (stepIndex.value === 1) return true; // TEMP: liberar navegacao para teste visual
  if (stepIndex.value === 2) return messagesValid.value;
  return true;
});
const audienceDescription = computed(() => {
  const selected = sourceCards.value.find(
    item => item.key === form.audience_type
  );
  if (form.audience_type === 'crm_stage' && selectedPipeline.value) {
    const stages = selectedPipeline.value.stages
      .filter(stage =>
        form.audience_config.stage_ids.some(
          id => Number(id) === Number(stage.id)
        )
      )
      .map(stage => stage.name)
      .join(', ');
    return stages
      ? `${selected.label} · ${selectedPipeline.value.name} · ${stages}`
      : selected.label;
  }
  return selected?.label || t('JRC_CAMPAIGNS.NOT_AVAILABLE');
});
const activeMessage = computed(
  () => form.steps[activeMessageIndex.value] || form.steps[0]
);
const eligibleCount = computed(() =>
  Number(audiencePreview.value.estimated_recipients || 0)
);
const estimatedMessageCount = computed(
  () => eligibleCount.value * form.steps.length
);
const rateRange = computed(() => {
  const minDelay = Number(form.delay_min_seconds);
  const maxDelay = Number(form.delay_max_seconds);
  const slow = maxDelay > 0 ? Math.floor(3600 / maxDelay) : null;
  const fast = minDelay > 0 ? Math.floor(3600 / minDelay) : null;
  if (!slow && !fast) return t('JRC_CAMPAIGNS.WIZARD.RATE_UNBOUNDED');
  if (!fast)
    return t('JRC_CAMPAIGNS.WIZARD.RATE_FROM', { value: formatNumber(slow) });
  return t('JRC_CAMPAIGNS.WIZARD.RATE_RANGE', {
    min: formatNumber(slow),
    max: formatNumber(fast),
  });
});
const estimatedDurationSeconds = computed(() => {
  if (!eligibleCount.value) return null;
  const averageDelay =
    (Number(form.delay_min_seconds) + Number(form.delay_max_seconds)) / 2;
  const sequenceDelay = form.steps.reduce((total, step) => {
    const followUpDelay = step.only_if_no_reply
      ? Number(step.follow_up_after_hours || 0) * 3600
      : 0;
    return total + Number(step.delay_after_seconds || 0) + followUpDelay;
  }, 0);
  return eligibleCount.value * averageDelay + sequenceDelay;
});
const durationLabel = computed(() =>
  formatDuration(estimatedDurationSeconds.value)
);
const selectedDaysLabel = computed(() =>
  form.sending_window.days
    .slice()
    .sort((a, b) => a - b)
    .map(day => t(`JRC_CAMPAIGNS.DAYS.${day}`))
    .join(', ')
);
const configuredInboxProblems = computed(() =>
  selectedSendingInboxes.value.filter(
    inbox => inboxHealth(inbox).state === 'error'
  )
);
const preflightItems = computed(() => {
  const items = [];
  if (!form.name.trim())
    items.push({
      severity: 'error',
      text: t('JRC_CAMPAIGNS.WIZARD.VALIDATION_NAME'),
    });
  if (!sourceValid.value)
    items.push({
      severity: 'error',
      text: t('JRC_CAMPAIGNS.WIZARD.VALIDATION_AUDIENCE'),
    });
  if (!form.inboxLinks.length)
    items.push({
      severity: 'error',
      text: t('JRC_CAMPAIGNS.WIZARD.VALIDATION_INBOX'),
    });
  if (!messagesValid.value)
    items.push({
      severity: 'error',
      text: t('JRC_CAMPAIGNS.WIZARD.VALIDATION_MESSAGE'),
    });
  if (audiencePreview.value.without_whatsapp_count)
    items.push({
      severity: 'warning',
      text: t('JRC_CAMPAIGNS.WIZARD.WARNING_NO_WHATSAPP', {
        count: formatNumber(audiencePreview.value.without_whatsapp_count),
      }),
    });
  if (audiencePreview.value.blacklisted_count)
    items.push({
      severity: 'warning',
      text: t('JRC_CAMPAIGNS.WIZARD.WARNING_BLACKLIST', {
        count: formatNumber(audiencePreview.value.blacklisted_count),
      }),
    });
  if (audiencePreview.value.blocked_count)
    items.push({
      severity: 'warning',
      text: t('JRC_CAMPAIGNS.WIZARD.WARNING_BLOCKED', {
        count: formatNumber(audiencePreview.value.blocked_count),
      }),
    });
  if (audiencePreview.value.duplicate_count)
    items.push({
      severity: 'warning',
      text: t('JRC_CAMPAIGNS.WIZARD.WARNING_DUPLICATES', {
        count: formatNumber(audiencePreview.value.duplicate_count),
      }),
    });
  if (configuredInboxProblems.value.length)
    items.push({
      severity: 'error',
      text: t('JRC_CAMPAIGNS.WIZARD.WARNING_INBOX_HEALTH', {
        count: configuredInboxProblems.value.length,
      }),
    });
  if (form.sending_window.days.length)
    items.push({
      severity: 'success',
      text: t('JRC_CAMPAIGNS.WIZARD.WINDOW_RESPECTED'),
    });
  return items;
});
const hasCriticalErrors = computed(() =>
  preflightItems.value.some(item => item.severity === 'error')
);
const jarvisMessage = computed(() => {
  if (stepIndex.value === 0) {
    if (audiencePreview.value.found_count === null)
      return t('JRC_CAMPAIGNS.WIZARD.JARVIS_AUDIENCE_WAITING');
    const excluded =
      Number(audiencePreview.value.found_count) - eligibleCount.value;
    return t('JRC_CAMPAIGNS.WIZARD.JARVIS_AUDIENCE', {
      found: formatNumber(audiencePreview.value.found_count),
      excluded: formatNumber(excluded),
    });
  }
  if (stepIndex.value === 1)
    return t('JRC_CAMPAIGNS.WIZARD.JARVIS_CONFIG', {
      boxes: form.inboxLinks.length,
      duration: durationLabel.value,
    });
  if (stepIndex.value === 2) {
    const variables = form.steps.reduce(
      (total, message) => total + variablesForMessage(message).length,
      0
    );
    return t(
      messagesValid.value
        ? 'JRC_CAMPAIGNS.WIZARD.JARVIS_MESSAGES_OK'
        : 'JRC_CAMPAIGNS.WIZARD.JARVIS_MESSAGES_PENDING',
      { messages: form.steps.length, variables }
    );
  }
  return t(
    hasCriticalErrors.value
      ? 'JRC_CAMPAIGNS.WIZARD.JARVIS_REVIEW_BLOCKED'
      : 'JRC_CAMPAIGNS.WIZARD.JARVIS_REVIEW_READY'
  );
});

const toggleArrayValue = (array, value) => {
  const index = array.findIndex(item => Number(item) === Number(value));
  if (index >= 0) array.splice(index, 1);
  else array.push(value);
};
const selectAudience = audienceType => {
  form.audience_type = audienceType;
};
const toggleSendingInbox = inbox => {
  const index = form.inboxLinks.findIndex(
    item => Number(item.inbox_id) === Number(inbox.id)
  );
  if (index >= 0) form.inboxLinks.splice(index, 1);
  else
    form.inboxLinks.push({
      id: null,
      inbox_id: inbox.id,
      weight: 1,
      position: form.inboxLinks.length,
      enabled: true,
    });
};
const moveInbox = (inboxId, direction) => {
  const index = form.inboxLinks.findIndex(
    item => Number(item.inbox_id) === Number(inboxId)
  );
  const target = index + direction;
  if (index < 0 || target < 0 || target >= form.inboxLinks.length) return;
  [form.inboxLinks[index], form.inboxLinks[target]] = [
    form.inboxLinks[target],
    form.inboxLinks[index],
  ];
};
const addMessage = () => {
  const message = defaultMessage();
  message.position = form.steps.length;
  form.steps.push(message);
  activeMessageIndex.value = form.steps.length - 1;
};
const removeMessage = index => {
  form.steps.splice(index, 1);
  form.steps.forEach((message, position) => {
    message.position = position;
  });
  activeMessageIndex.value = Math.max(
    0,
    Math.min(activeMessageIndex.value, form.steps.length - 1)
  );
};
const moveMessage = (index, direction) => {
  const target = index + direction;
  if (target < 0 || target >= form.steps.length) return;
  [form.steps[index], form.steps[target]] = [
    form.steps[target],
    form.steps[index],
  ];
  form.steps.forEach((message, position) => {
    message.position = position;
  });
  activeMessageIndex.value = target;
};
const hydrateMappings = message => {
  const bodyParams = message.template_params?.processed_params?.body || {};
  variablesForMessage(message).forEach(variable => {
    const value = bodyParams[variable] ?? bodyParams[String(variable)];
    if (mappingOptions.value.some(option => option.value === value))
      message.variableMappings[variable] = value;
    else if (value !== undefined && value !== null && value !== '') {
      message.variableMappings[variable] = '__custom__';
      message.variableValues[variable] = String(value);
    } else message.variableMappings[variable] ||= '';
  });
};
const selectTemplate = (message, value) => {
  const [name, language] = value.split('::');
  const template = templates.value.find(
    item => item.name === name && item.language === language
  );
  message.template_name = template?.name || '';
  message.template_language = template?.language || 'pt_BR';
  message.template_namespace = template?.namespace || '';
  message.variableMappings = {};
  message.variableValues = {};
  hydrateMappings(message);
};
const selectInboxTemplate = (message, inbox, value) => {
  const [name, language] = value.split('::');
  const template = (inbox.templates || []).find(
    item => item.name === name && item.language === language
  );
  const overrides = { ...message.inbox_overrides };
  if (!template) delete overrides[inbox.id];
  else
    overrides[inbox.id] = {
      ...(overrides[inbox.id] || {}),
      template_name: template.name,
      template_language: template.language,
      template_namespace: template.namespace || '',
    };
  message.inbox_overrides = overrides;
};
const uploadMedia = async (event, message, index) => {
  const file = event.target.files?.[0];
  if (!file) return;
  uploadingStep.value = index;
  try {
    const { data } = await JrcCampaignsAPI.uploadMedia(file, message.kind);
    message.media_url = data.url;
    message.file_name = data.file_name;
    useAlert(t('JRC_CAMPAIGNS.ALERTS.MEDIA_UPLOADED'));
  } finally {
    uploadingStep.value = null;
    event.target.value = '';
  }
};
const parseTemplateParams = message => {
  try {
    return JSON.parse(message.templateParamsText || '{}');
  } catch {
    return {};
  }
};
const buildTemplateParams = message => {
  const params = parseTemplateParams(message);
  const variables = variablesForMessage(message);
  if (!variables.length) return params;
  const body = {};
  variables.forEach(variable => {
    const mapping = message.variableMappings[variable];
    body[variable] =
      mapping === '__custom__' ? message.variableValues[variable] : mapping;
  });
  return {
    ...params,
    processed_params: { ...(params.processed_params || {}), body },
  };
};
const syncAdvancedParams = message => {
  message.templateParamsText = JSON.stringify(
    buildTemplateParams(message),
    null,
    2
  );
  message.advancedOpen = !message.advancedOpen;
};
const serializeStep = (message, position = 0) => ({
  id: message.id,
  position,
  kind: message.kind,
  body: message.body,
  media_url: message.media_url,
  file_name: message.file_name,
  template_name: message.template_name,
  template_namespace: message.template_namespace,
  template_language: message.template_language,
  template_params: buildTemplateParams(message),
  inbox_overrides: message.inbox_overrides || {},
  delay_after_seconds: Number(message.delay_after_seconds) || 0,
  only_if_no_reply: Boolean(message.only_if_no_reply),
  follow_up_after_hours: message.only_if_no_reply
    ? Number(message.follow_up_after_hours || 24)
    : null,
});
const buildPayload = () => {
  const existingInboxLinks = props.campaign?.campaign_inboxes || [];
  const inboxAttributes = form.inboxLinks.map((item, position) => ({
    ...item,
    position,
  }));
  existingInboxLinks.forEach(existing => {
    if (!form.inboxLinks.some(item => Number(item.id) === Number(existing.id)))
      inboxAttributes.push({ id: existing.id, _destroy: true });
  });
  const existingSteps = props.campaign?.steps || [];
  const stepAttributes = form.steps.map(serializeStep);
  existingSteps.forEach(existing => {
    if (!form.steps.some(item => Number(item.id) === Number(existing.id)))
      stepAttributes.push({ id: existing.id, _destroy: true });
  });
  return {
    name: form.name,
    audience_type: form.audience_type,
    audience_config: form.audience_config,
    rotation_mode: form.rotation_mode,
    delay_min_seconds: Number(form.delay_min_seconds),
    delay_max_seconds: Number(form.delay_max_seconds),
    sending_window: form.sending_window,
    conversation_mode: form.conversation_mode,
    trigger_type: form.trigger_type,
    scheduled_at:
      form.trigger_type === 'scheduled' && form.scheduled_at
        ? new Date(form.scheduled_at).toISOString()
        : null,
    recurrence_config: form.recurrence_config,
    follow_up_config: form.follow_up_config,
    campaign_inboxes_attributes: inboxAttributes,
    steps_attributes: stepAttributes,
  };
};
const refreshAudiencePreview = async () => {
  if (!sourceValid.value) return;
  previewingAudience.value = true;
  try {
    const { data } = await JrcCampaignsAPI.audiencePreview({
      audience_type: form.audience_type,
      audience_config: form.audience_config,
    });
    audiencePreview.value = data;
  } catch {
    audiencePreview.value = {
      ...audiencePreview.value,
      found_count: null,
      estimated_recipients: null,
      sample: [],
    };
  } finally {
    previewingAudience.value = false;
  }
};
const nextStep = async () => {
  if (!currentStepValid.value) return;
  if (stepIndex.value === 0) await refreshAudiencePreview();
  stepIndex.value += 1;
};
const goToStep = index => {
  if (index <= stepIndex.value) stepIndex.value = index;
};
const save = async startAfterSave => {
  if (
    !form.name.trim() ||
    !sourceValid.value ||
    !configValid.value ||
    !messagesValid.value
  )
    return;
  saving.value = true;
  try {
    const payload = { campaign: buildPayload() };
    const response = props.campaign
      ? await JrcCampaignsAPI.update(props.campaign.id, payload)
      : await JrcCampaignsAPI.create(payload);
    useAlert(
      t(
        props.campaign
          ? 'JRC_CAMPAIGNS.ALERTS.UPDATED'
          : 'JRC_CAMPAIGNS.ALERTS.SAVED'
      )
    );
    emit('saved', startAfterSave ? response.data : null);
  } catch (error) {
    useAlert(
      error?.response?.data?.errors?.join(', ') ||
        t('JRC_CAMPAIGNS.ALERTS.ACTION_FAILED')
    );
  } finally {
    saving.value = false;
  }
};
const sendTest = async (message = activeMessage.value) => {
  if (!testPhone.value.trim()) {
    useAlert(t('JRC_CAMPAIGNS.ALERTS.TEST_PHONE_REQUIRED'));
    return;
  }
  if (!message || !messageValid(message) || !form.inboxLinks.length) {
    useAlert(t('JRC_CAMPAIGNS.ALERTS.TEST_CONFIG_REQUIRED'));
    return;
  }
  testSending.value = true;
  try {
    await JrcCampaignsAPI.testMessage({
      phone_number: testPhone.value,
      inbox_id: form.inboxLinks[0].inbox_id,
      step: serializeStep(message),
    });
    useAlert(t('JRC_CAMPAIGNS.ALERTS.TEST_SENT'));
  } catch (error) {
    useAlert(
      error?.response?.data?.errors?.join(', ') ||
        t('JRC_CAMPAIGNS.ALERTS.TEST_FAILED')
    );
  } finally {
    testSending.value = false;
  }
};
const validateMessage = message => {
  useAlert(
    t(
      messageValid(message)
        ? 'JRC_CAMPAIGNS.ALERTS.MESSAGE_VALID'
        : 'JRC_CAMPAIGNS.ALERTS.MESSAGE_INVALID'
    )
  );
};
const previewVariableValue = (message, variable) => {
  const mapping = message.variableMappings[variable];
  if (mapping === '__custom__')
    return message.variableValues[variable] || `{{${variable}}}`;
  const values = {
    '{{nome}}':
      audiencePreview.value.sample?.[0]?.name ||
      t('JRC_CAMPAIGNS.WIZARD.PREVIEW_CONTACT'),
    '{{telefone}}':
      audiencePreview.value.sample?.[0]?.phone_number ||
      t('JRC_CAMPAIGNS.WIZARD.PREVIEW_PHONE'),
    '{{email}}': t('JRC_CAMPAIGNS.WIZARD.PREVIEW_EMAIL'),
    '{{account.name}}':
      props.metadata.account_name || t('JRC_CAMPAIGNS.WIZARD.PREVIEW_ACCOUNT'),
    '{{inbox.name}}':
      selectedSendingInboxes.value[0]?.name ||
      t('JRC_CAMPAIGNS.WIZARD.PREVIEW_INBOX'),
  };
  return values[mapping] || `{{${variable}}}`;
};
const previewText = message => {
  let content =
    message.kind === 'template'
      ? templateBody(templateForMessage(message))
      : message.body;
  if (!content && message.kind !== 'template')
    return (
      message.file_name ||
      message.media_url ||
      t('JRC_CAMPAIGNS.WIZARD.PREVIEW_EMPTY')
    );
  variablesForMessage(message).forEach(variable => {
    content = content.replace(
      new RegExp(
        `\\{\\{\\s*${variable.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\s*\\}\\}`,
        'g'
      ),
      previewVariableValue(message, variable)
    );
  });
  return content
    .replace(/\{\{\s*nome\s*\}\}/g, previewVariableValue(message, 'nome'))
    .replace(
      /\{\{\s*telefone\s*\}\}/g,
      previewVariableValue(message, 'telefone')
    )
    .replace(/\{\{\s*email\s*\}\}/g, previewVariableValue(message, 'email'));
};
const messageTypeLabel = kind =>
  t(`JRC_CAMPAIGNS.WIZARD.TYPE_${kind.toUpperCase()}`);
const hydrate = campaign => {
  if (!campaign) return;
  form.name = campaign.name || '';
  form.audience_type = campaign.audience_type || 'all_contacts';
  form.audience_config = {
    label_ids: campaign.audience_config?.label_ids || [],
    inbox_ids: campaign.audience_config?.inbox_ids || [],
    pipeline_id: campaign.audience_config?.pipeline_id || null,
    stage_ids: campaign.audience_config?.stage_ids || [],
    sanitized_list_id: campaign.audience_config?.sanitized_list_id || null,
    customer_filters: campaign.audience_config?.customer_filters || {},
  };
  form.inboxLinks = (campaign.campaign_inboxes || []).map(item => ({
    ...item,
  }));
  form.rotation_mode = campaign.rotation_mode || 'round_robin';
  form.delay_min_seconds = campaign.delay_min_seconds ?? 5;
  form.delay_max_seconds = campaign.delay_max_seconds ?? 20;
  form.sending_window = campaign.sending_window || {
    start: '08:00',
    end: '18:00',
    days: [1, 2, 3, 4, 5],
  };
  form.conversation_mode = campaign.conversation_mode || 'reply_only';
  form.trigger_type = campaign.trigger_type || 'manual';
  form.scheduled_at = campaign.scheduled_at
    ? new Date(campaign.scheduled_at).toISOString().slice(0, 16)
    : '';
  form.recurrence_config = {
    type: 'none',
    interval_days: 7,
    ...(campaign.recurrence_config || {}),
  };
  form.follow_up_config = {
    on_reply_label_id: null,
    on_reply_stage_id: null,
    ...(campaign.follow_up_config || {}),
  };
  form.steps = (
    campaign.steps?.length ? campaign.steps : [defaultMessage()]
  ).map((message, position) => {
    const hydrated = {
      ...defaultMessage(),
      ...message,
      position,
      variableMappings: {},
      variableValues: {},
      templateParamsText: JSON.stringify(
        message.template_params || {},
        null,
        2
      ),
    };
    return hydrated;
  });
  form.steps.forEach(hydrateMappings);
};

hydrate(props.campaign);
watch(
  () => form.audience_config.pipeline_id,
  (value, previous) => {
    if (previous !== undefined && Number(value) !== Number(previous))
      form.audience_config.stage_ids = [];
  }
);
watch(
  [() => form.audience_type, () => form.audience_config],
  () => {
    window.clearTimeout(audienceTimer);
    if (!sourceValid.value) return;
    audienceTimer = window.setTimeout(refreshAudiencePreview, 450);
  },
  { deep: true }
);
onMounted(refreshAudiencePreview);
watch(
  () => form.audience_type,
  value => {
    if (value === 'sanitized_list') form.audience_config.customer_filters = {};
  }
);
onBeforeUnmount(() => window.clearTimeout(audienceTimer));
</script>

<template>
  <div
    class="absolute inset-0 z-40 flex flex-col overflow-hidden bg-n-background"
  >
    <header class="border-b border-n-weak bg-n-background px-5 py-4 lg:px-8">
      <div class="flex items-center justify-between gap-4">
        <div class="flex min-w-0 items-center gap-3">
          <button
            type="button"
            class="rounded-xl border border-n-weak p-2 text-n-slate-11 hover:bg-n-alpha-2"
            :title="$t('JRC_CAMPAIGNS.CLOSE')"
            @click="emit('close')"
          >
            <span class="i-lucide-arrow-left size-5" />
          </button>
          <div class="min-w-0">
            <p
              class="text-[11px] font-semibold uppercase tracking-wide text-n-brand"
            >
              {{ $t('JRC_CAMPAIGNS.WIZARD.CAMPAIGN_BUILDER') }}
            </p>
            <h2 class="truncate text-xl font-semibold text-n-slate-12">
              {{
                $t(
                  campaign
                    ? 'JRC_CAMPAIGNS.WIZARD.EDIT_TITLE'
                    : 'JRC_CAMPAIGNS.WIZARD.NEW_TITLE'
                )
              }}
            </h2>
          </div>
        </div>
        <button
          type="button"
          class="rounded-xl p-2 text-n-slate-10 hover:bg-n-alpha-2"
          :title="$t('JRC_CAMPAIGNS.CLOSE')"
          @click="emit('close')"
        >
          <span class="i-lucide-x size-5" />
        </button>
      </div>
      <nav class="mx-auto mt-5 flex max-w-4xl items-center">
        <template v-for="(step, index) in wizardSteps" :key="step.label">
          <button
            type="button"
            class="flex min-w-0 items-center gap-2"
            :class="index <= stepIndex ? 'text-n-brand' : 'text-n-slate-9'"
            :disabled="index > stepIndex"
            @click="goToStep(index)"
          >
            <span
              class="flex size-8 shrink-0 items-center justify-center rounded-full border text-xs font-semibold"
              :class="
                index === stepIndex
                  ? 'border-n-brand bg-n-brand text-white'
                  : index < stepIndex
                    ? 'border-n-brand bg-n-brand/10'
                    : 'border-n-weak bg-n-alpha-1'
              "
              >{{ index + 1 }}</span
            >
            <span class="hidden text-xs font-medium sm:block">{{
              step.label
            }}</span>
          </button>
          <span
            v-if="index < wizardSteps.length - 1"
            class="mx-3 h-px flex-1"
            :class="index < stepIndex ? 'bg-n-brand' : 'bg-n-weak'"
          />
        </template>
      </nav>
    </header>

    <main class="flex-1 overflow-y-auto">
      <div
        class="mx-auto grid w-full max-w-[1540px] gap-5 p-5 lg:grid-cols-12 lg:p-8"
      >
        <section class="lg:col-span-9">
          <div v-if="stepIndex === 0" class="space-y-5">
            <div>
              <h3 class="text-xl font-semibold text-n-slate-12">
                {{ $t('JRC_CAMPAIGNS.WIZARD.AUDIENCE_TITLE') }}
              </h3>
              <p class="mt-1 text-sm text-n-slate-10">
                {{ $t('JRC_CAMPAIGNS.WIZARD.AUDIENCE_SUBTITLE') }}
              </p>
            </div>
            <label class="block max-w-2xl text-sm font-medium text-n-slate-12"
              >{{ $t('JRC_CAMPAIGNS.WIZARD.NAME')
              }}<input
                v-model="form.name"
                class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-background px-3 py-2.5"
                :placeholder="$t('JRC_CAMPAIGNS.WIZARD.NAME_PLACEHOLDER')"
            /></label>
            <div class="rounded-2xl border border-n-weak p-5">
              <h4 class="text-sm font-semibold text-n-slate-12">
                {{ $t('JRC_CAMPAIGNS.WIZARD.SOURCE') }}
              </h4>
              <div class="mt-4 grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
                <button
                  v-for="source in sourceCards"
                  :key="source.key"
                  type="button"
                  class="relative rounded-xl border p-4 text-left transition-colors"
                  :class="
                    form.audience_type === source.key
                      ? 'border-n-brand bg-n-brand/5'
                      : 'border-n-weak hover:border-n-strong'
                  "
                  @click="selectAudience(source.key)"
                >
                  <span
                    class="flex size-9 items-center justify-center rounded-xl bg-n-alpha-2 text-n-slate-11"
                    ><span class="size-5" :class="[source.icon]" /></span
                  ><span
                    class="mt-3 block text-sm font-semibold text-n-slate-12"
                    >{{ source.label }}</span
                  ><span class="mt-1 block text-xs leading-5 text-n-slate-10">{{
                    source.description
                  }}</span
                  ><span
                    v-if="form.audience_type === source.key"
                    class="i-lucide-circle-check absolute right-3 top-3 size-5 text-n-brand"
                  />
                </button>
              </div>
              <div
                v-if="form.audience_type === 'label'"
                class="mt-5 border-t border-n-weak pt-5"
              >
                <p class="mb-3 text-sm font-medium text-n-slate-12">
                  {{ $t('JRC_CAMPAIGNS.WIZARD.SELECT_LABELS') }}
                </p>
                <div class="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
                  <label
                    v-for="label in metadata.labels"
                    :key="label.id"
                    class="flex items-center gap-2 rounded-xl border border-n-weak p-3 text-sm"
                    ><input
                      type="checkbox"
                      :checked="
                        form.audience_config.label_ids.some(
                          id => Number(id) === Number(label.id)
                        )
                      "
                      @change="
                        toggleArrayValue(
                          form.audience_config.label_ids,
                          label.id
                        )
                      "
                    /><span>{{ label.title }}</span></label
                  >
                </div>
              </div>
              <div
                v-if="form.audience_type === 'inbox'"
                class="mt-5 border-t border-n-weak pt-5"
              >
                <p class="mb-3 text-sm font-medium text-n-slate-12">
                  {{ $t('JRC_CAMPAIGNS.WIZARD.SELECT_SOURCE_INBOXES') }}
                </p>
                <div class="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
                  <label
                    v-for="inbox in metadata.source_inboxes || metadata.inboxes"
                    :key="inbox.id"
                    class="flex items-center gap-2 rounded-xl border border-n-weak p-3 text-sm"
                    ><input
                      type="checkbox"
                      :checked="
                        form.audience_config.inbox_ids.some(
                          id => Number(id) === Number(inbox.id)
                        )
                      "
                      @change="
                        toggleArrayValue(
                          form.audience_config.inbox_ids,
                          inbox.id
                        )
                      "
                    /><span>{{ inbox.name }}</span></label
                  >
                </div>
              </div>
              <div
                v-if="form.audience_type === 'crm_stage'"
                class="mt-5 grid gap-4 border-t border-n-weak pt-5 md:grid-cols-2"
              >
                <label class="text-sm font-medium text-n-slate-12"
                  >{{ $t('JRC_CAMPAIGNS.WIZARD.PIPELINE')
                  }}<select
                    v-model="form.audience_config.pipeline_id"
                    class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-background px-3 py-2.5"
                  >
                    <option :value="null">
                      {{ $t('JRC_CAMPAIGNS.WIZARD.SELECT_OPTION') }}
                    </option>
                    <option
                      v-for="pipeline in metadata.pipelines"
                      :key="pipeline.id"
                      :value="pipeline.id"
                    >
                      {{ pipeline.name }}
                    </option>
                  </select></label
                >
                <div>
                  <p class="mb-2 text-sm font-medium text-n-slate-12">
                    {{ $t('JRC_CAMPAIGNS.WIZARD.STAGES') }}
                  </p>
                  <label
                    v-for="stage in selectedPipeline?.stages || []"
                    :key="stage.id"
                    class="mb-2 flex items-center gap-2 rounded-xl border border-n-weak p-2.5 text-sm"
                    ><input
                      type="checkbox"
                      :checked="
                        form.audience_config.stage_ids.some(
                          id => Number(id) === Number(stage.id)
                        )
                      "
                      @change="
                        toggleArrayValue(
                          form.audience_config.stage_ids,
                          stage.id
                        )
                      "
                    /><span>{{ stage.name }}</span></label
                  >
                </div>
              </div>
              <label
                v-if="form.audience_type === 'sanitized_list'"
                class="mt-5 block max-w-xl border-t border-n-weak pt-5 text-sm font-medium text-n-slate-12"
                >{{ $t('JRC_CAMPAIGNS.WIZARD.SANITIZED_LIST')
                }}<select
                  v-model="form.audience_config.sanitized_list_id"
                  class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-background px-3 py-2.5"
                >
                  <option :value="null">
                    {{ $t('JRC_CAMPAIGNS.WIZARD.SELECT_OPTION') }}
                  </option>
                  <option
                    v-for="list in metadata.sanitized_lists"
                    :key="list.id"
                    :value="list.id"
                  >
                    {{ list.name }}
                  </option>
                </select></label
              >
            </div>
            <CampaignFilters
              v-if="
                hasCustomerMaster && form.audience_type !== 'sanitized_list'
              "
              v-model="form.audience_config.customer_filters"
            />
            <div class="rounded-2xl border border-n-weak p-5">
              <div class="flex items-center justify-between gap-3">
                <div>
                  <h4 class="text-sm font-semibold text-n-slate-12">
                    {{ $t('JRC_CAMPAIGNS.WIZARD.AUDIENCE_PREVIEW') }}
                  </h4>
                  <p class="mt-1 text-xs text-n-slate-10">
                    {{ $t('JRC_CAMPAIGNS.WIZARD.AUDIENCE_PREVIEW_HELP') }}
                  </p>
                </div>
                <button
                  type="button"
                  class="rounded-xl border border-n-strong px-3 py-2 text-xs font-medium text-n-slate-11"
                  :disabled="previewingAudience || !sourceValid"
                  @click="refreshAudiencePreview"
                >
                  <span
                    class="i-lucide-refresh-cw mr-1 inline-block size-3"
                    :class="{ 'animate-spin': previewingAudience }"
                  />{{ $t('JRC_CAMPAIGNS.REFRESH') }}
                </button>
              </div>
              <div class="mt-4 grid gap-3 sm:grid-cols-2 xl:grid-cols-5">
                <div
                  v-for="item in [
                    {
                      key: 'found_count',
                      label: $t('JRC_CAMPAIGNS.WIZARD.FOUND'),
                      className: 'text-n-blue-11',
                    },
                    {
                      key: 'estimated_recipients',
                      label: $t('JRC_CAMPAIGNS.WIZARD.ELIGIBLE'),
                      className: 'text-n-teal-11',
                    },
                    {
                      key: 'without_whatsapp_count',
                      label: $t('JRC_CAMPAIGNS.WIZARD.NO_WHATSAPP'),
                      className: 'text-n-amber-11',
                    },
                    {
                      key: 'blacklisted_count',
                      label: $t('JRC_CAMPAIGNS.WIZARD.BLACKLISTED'),
                      className: 'text-n-ruby-11',
                    },
                    {
                      key: 'duplicate_count',
                      label: $t('JRC_CAMPAIGNS.WIZARD.DUPLICATES'),
                      className: 'text-n-slate-11',
                    },
                  ]"
                  :key="item.key"
                  class="rounded-xl bg-n-alpha-1 p-4"
                >
                  <p class="text-xs text-n-slate-10">{{ item.label }}</p>
                  <p class="mt-2 text-xl font-semibold" :class="item.className">
                    {{
                      audiencePreview[item.key] === null
                        ? '—'
                        : formatNumber(audiencePreview[item.key])
                    }}
                  </p>
                </div>
              </div>
              <button
                v-if="audiencePreview.sample?.length"
                type="button"
                class="mt-4 text-xs font-medium text-n-brand"
                @click="showAudienceSample = !showAudienceSample"
              >
                {{
                  $t(
                    showAudienceSample
                      ? 'JRC_CAMPAIGNS.WIZARD.HIDE_CONTACTS'
                      : 'JRC_CAMPAIGNS.WIZARD.VIEW_CONTACTS'
                  )
                }}
              </button>
              <div
                v-if="showAudienceSample"
                class="mt-3 overflow-hidden rounded-xl border border-n-weak"
              >
                <div
                  v-for="contact in audiencePreview.sample"
                  :key="contact.phone_number"
                  class="flex items-center justify-between border-b border-n-weak px-3 py-2 text-xs last:border-b-0"
                >
                  <span class="font-medium text-n-slate-12">{{
                    contact.name || $t('JRC_CAMPAIGNS.WIZARD.UNNAMED_CONTACT')
                  }}</span
                  ><span class="text-n-slate-10">{{
                    contact.phone_number
                  }}</span>
                </div>
              </div>
            </div>
          </div>

          <div v-else-if="stepIndex === 1" class="space-y-5">
            <div>
              <h3 class="text-xl font-semibold text-n-slate-12">
                {{ $t('JRC_CAMPAIGNS.WIZARD.CONFIG_TITLE') }}
              </h3>
              <p class="mt-1 text-sm text-n-slate-10">
                {{ $t('JRC_CAMPAIGNS.WIZARD.CONFIG_SUBTITLE') }}
              </p>
            </div>
            <div class="grid gap-4 xl:grid-cols-3">
              <article class="rounded-2xl border border-n-weak p-5">
                <h4 class="text-sm font-semibold text-n-slate-12">
                  {{ $t('JRC_CAMPAIGNS.WIZARD.SENDING_INBOXES') }}
                </h4>
                <p class="mt-1 text-xs text-n-slate-10">
                  {{ $t('JRC_CAMPAIGNS.WIZARD.SENDING_INBOXES_HELP') }}
                </p>
                <div class="mt-4 space-y-2">
                  <div
                    v-for="inbox in metadata.inboxes"
                    :key="inbox.id"
                    class="rounded-xl border border-n-weak p-3"
                  >
                    <label class="flex items-start gap-3"
                      ><input
                        type="checkbox"
                        class="mt-1"
                        :checked="selectedInboxIds.includes(Number(inbox.id))"
                        @change="toggleSendingInbox(inbox)"
                      /><span class="min-w-0 flex-1"
                        ><span
                          class="block truncate text-sm font-medium text-n-slate-12"
                          >{{ inbox.name }}</span
                        ><span class="block truncate text-xs text-n-slate-9"
                          >{{ inbox.phone_number }} · {{ inbox.provider }}</span
                        ></span
                      ><span
                        class="rounded-full px-2 py-1 text-[10px] font-medium"
                        :class="inboxHealth(inbox).className"
                        >{{ inboxHealth(inbox).label }}</span
                      ></label
                    >
                    <div
                      v-if="
                        form.rotation_mode === 'priority' &&
                        selectedInboxIds.includes(Number(inbox.id))
                      "
                      class="mt-2 flex justify-end gap-1"
                    >
                      <button
                        type="button"
                        class="rounded p-1 text-n-slate-10 hover:bg-n-alpha-2"
                        :title="$t('JRC_CAMPAIGNS.WIZARD.MOVE_UP')"
                        @click="moveInbox(inbox.id, -1)"
                      >
                        <span class="i-lucide-arrow-up size-3" /></button
                      ><button
                        type="button"
                        class="rounded p-1 text-n-slate-10 hover:bg-n-alpha-2"
                        :title="$t('JRC_CAMPAIGNS.WIZARD.MOVE_DOWN')"
                        @click="moveInbox(inbox.id, 1)"
                      >
                        <span class="i-lucide-arrow-down size-3" />
                      </button>
                    </div>
                  </div>
                </div>
              </article>
              <article class="rounded-2xl border border-n-weak p-5">
                <h4 class="text-sm font-semibold text-n-slate-12">
                  {{ $t('JRC_CAMPAIGNS.WIZARD.ROTATION') }}
                </h4>
                <div class="mt-4 space-y-2">
                  <label
                    v-for="mode in rotationModes"
                    :key="mode.key"
                    class="flex cursor-pointer gap-3 rounded-xl border p-3"
                    :class="
                      form.rotation_mode === mode.key
                        ? 'border-n-brand bg-n-brand/5'
                        : 'border-n-weak'
                    "
                    ><input
                      v-model="form.rotation_mode"
                      type="radio"
                      :value="mode.key"
                      class="mt-1"
                    /><span
                      ><span
                        class="block text-sm font-medium text-n-slate-12"
                        >{{ mode.label }}</span
                      ><span
                        class="mt-1 block text-xs leading-5 text-n-slate-10"
                        >{{ mode.description }}</span
                      ></span
                    ></label
                  >
                </div>
                <div
                  v-if="['random', 'weighted'].includes(form.rotation_mode)"
                  class="mt-3 rounded-xl bg-n-amber-2 p-3 text-xs text-n-amber-11"
                >
                  {{ $t('JRC_CAMPAIGNS.WIZARD.LEGACY_ROTATION') }}
                </div>
              </article>
              <article class="rounded-2xl border border-n-weak p-5">
                <h4 class="text-sm font-semibold text-n-slate-12">
                  {{ $t('JRC_CAMPAIGNS.WIZARD.RHYTHM') }}
                </h4>
                <div class="mt-4 grid grid-cols-2 gap-3">
                  <label class="text-xs font-medium text-n-slate-10"
                    >{{ $t('JRC_CAMPAIGNS.WIZARD.DELAY_MIN')
                    }}<input
                      v-model.number="form.delay_min_seconds"
                      type="number"
                      min="0"
                      class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-background px-3 py-2.5 text-sm text-n-slate-12" /></label
                  ><label class="text-xs font-medium text-n-slate-10"
                    >{{ $t('JRC_CAMPAIGNS.WIZARD.DELAY_MAX')
                    }}<input
                      v-model.number="form.delay_max_seconds"
                      type="number"
                      min="0"
                      class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-background px-3 py-2.5 text-sm text-n-slate-12"
                  /></label>
                </div>
                <div class="mt-4 rounded-xl bg-n-blue-2 p-4">
                  <p class="text-xs text-n-blue-11">
                    {{ $t('JRC_CAMPAIGNS.WIZARD.ESTIMATED_RATE') }}
                  </p>
                  <p class="mt-1 text-lg font-semibold text-n-slate-12">
                    {{ rateRange }}
                  </p>
                  <p class="mt-1 text-xs text-n-slate-9">
                    {{ $t('JRC_CAMPAIGNS.WIZARD.GLOBAL_RATE_HELP') }}
                  </p>
                </div>
              </article>
            </div>
            <div class="grid gap-4 xl:grid-cols-2">
              <article class="rounded-2xl border border-n-weak p-5">
                <h4 class="text-sm font-semibold text-n-slate-12">
                  {{ $t('JRC_CAMPAIGNS.WIZARD.WINDOW') }}
                </h4>
                <div class="mt-4 grid grid-cols-2 gap-4">
                  <label class="text-xs font-medium text-n-slate-10"
                    >{{ $t('JRC_CAMPAIGNS.WIZARD.WINDOW_START')
                    }}<input
                      v-model="form.sending_window.start"
                      type="time"
                      class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-background px-3 py-2.5 text-sm" /></label
                  ><label class="text-xs font-medium text-n-slate-10"
                    >{{ $t('JRC_CAMPAIGNS.WIZARD.WINDOW_END')
                    }}<input
                      v-model="form.sending_window.end"
                      type="time"
                      class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-background px-3 py-2.5 text-sm"
                  /></label>
                </div>
                <div class="mt-4 flex flex-wrap gap-2">
                  <label
                    v-for="day in [1, 2, 3, 4, 5, 6, 0]"
                    :key="day"
                    class="flex cursor-pointer items-center gap-2 rounded-xl border px-3 py-2 text-xs"
                    :class="
                      form.sending_window.days.includes(day)
                        ? 'border-n-brand bg-n-brand/5 text-n-brand'
                        : 'border-n-weak text-n-slate-10'
                    "
                    ><input
                      type="checkbox"
                      class="sr-only"
                      :checked="form.sending_window.days.includes(day)"
                      @change="toggleArrayValue(form.sending_window.days, day)"
                    />{{ $t(`JRC_CAMPAIGNS.DAYS.${day}`) }}</label
                  >
                </div>
              </article>
              <article class="rounded-2xl border border-n-weak p-5">
                <h4 class="text-sm font-semibold text-n-slate-12">
                  {{ $t('JRC_CAMPAIGNS.WIZARD.OPERATION') }}
                </h4>
                <div class="mt-4 grid gap-3 sm:grid-cols-2">
                  <label class="text-xs font-medium text-n-slate-10"
                    >{{ $t('JRC_CAMPAIGNS.WIZARD.CONVERSATION_MODE')
                    }}<select
                      v-model="form.conversation_mode"
                      class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-background px-3 py-2.5 text-sm"
                    >
                      <option value="reply_only">
                        {{ $t('JRC_CAMPAIGNS.WIZARD.REPLY_ONLY') }}
                      </option>
                      <option value="pending">
                        {{ $t('JRC_CAMPAIGNS.WIZARD.PENDING') }}
                      </option>
                      <option value="open">
                        {{ $t('JRC_CAMPAIGNS.WIZARD.OPEN') }}
                      </option>
                    </select></label
                  ><label class="text-xs font-medium text-n-slate-10"
                    >{{ $t('JRC_CAMPAIGNS.WIZARD.TRIGGER')
                    }}<select
                      v-model="form.trigger_type"
                      class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-background px-3 py-2.5 text-sm"
                    >
                      <option value="manual">
                        {{ $t('JRC_CAMPAIGNS.WIZARD.MANUAL') }}
                      </option>
                      <option value="scheduled">
                        {{ $t('JRC_CAMPAIGNS.WIZARD.SCHEDULED') }}
                      </option>
                    </select></label
                  ><label
                    v-if="form.trigger_type === 'scheduled'"
                    class="text-xs font-medium text-n-slate-10"
                    >{{ $t('JRC_CAMPAIGNS.WIZARD.SCHEDULED_AT')
                    }}<input
                      v-model="form.scheduled_at"
                      type="datetime-local"
                      class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-background px-3 py-2.5 text-sm" /></label
                  ><label class="text-xs font-medium text-n-slate-10"
                    >{{ $t('JRC_CAMPAIGNS.WIZARD.RECURRENCE')
                    }}<select
                      v-model="form.recurrence_config.type"
                      class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-background px-3 py-2.5 text-sm"
                    >
                      <option value="none">
                        {{ $t('JRC_CAMPAIGNS.WIZARD.NONE') }}
                      </option>
                      <option value="daily">
                        {{ $t('JRC_CAMPAIGNS.WIZARD.DAILY') }}
                      </option>
                      <option value="weekly">
                        {{ $t('JRC_CAMPAIGNS.WIZARD.WEEKLY') }}
                      </option>
                      <option value="monthly">
                        {{ $t('JRC_CAMPAIGNS.WIZARD.MONTHLY') }}
                      </option>
                      <option value="custom">
                        {{ $t('JRC_CAMPAIGNS.WIZARD.CUSTOM') }}
                      </option>
                    </select></label
                  ><label
                    v-if="form.recurrence_config.type === 'custom'"
                    class="text-xs font-medium text-n-slate-10"
                    >{{ $t('JRC_CAMPAIGNS.WIZARD.CUSTOM_INTERVAL_DAYS')
                    }}<input
                      v-model.number="form.recurrence_config.interval_days"
                      type="number"
                      min="1"
                      class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-background px-3 py-2.5 text-sm"
                  /></label>
                </div>
              </article>
            </div>
            <article class="rounded-2xl border border-n-weak p-5">
              <h4 class="text-sm font-semibold text-n-slate-12">
                {{ $t('JRC_CAMPAIGNS.WIZARD.ON_REPLY_ACTIONS') }}
              </h4>
              <p class="mt-1 text-xs text-n-slate-10">
                {{ $t('JRC_CAMPAIGNS.WIZARD.ON_REPLY_HELP') }}
              </p>
              <div class="mt-4 grid gap-4 md:grid-cols-2">
                <label class="text-xs font-medium text-n-slate-10"
                  >{{ $t('JRC_CAMPAIGNS.WIZARD.ON_REPLY_LABEL')
                  }}<select
                    v-model="form.follow_up_config.on_reply_label_id"
                    class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-background px-3 py-2.5 text-sm"
                  >
                    <option :value="null">
                      {{ $t('JRC_CAMPAIGNS.WIZARD.NO_ACTION') }}
                    </option>
                    <option
                      v-for="label in metadata.labels"
                      :key="label.id"
                      :value="label.id"
                    >
                      {{ label.title }}
                    </option>
                  </select></label
                ><label class="text-xs font-medium text-n-slate-10"
                  >{{ $t('JRC_CAMPAIGNS.WIZARD.ON_REPLY_STAGE')
                  }}<select
                    v-model="form.follow_up_config.on_reply_stage_id"
                    class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-background px-3 py-2.5 text-sm"
                  >
                    <option :value="null">
                      {{ $t('JRC_CAMPAIGNS.WIZARD.NO_ACTION') }}
                    </option>
                    <option
                      v-for="stage in allStages"
                      :key="stage.id"
                      :value="stage.id"
                    >
                      {{ stage.name }}
                    </option>
                  </select></label
                >
              </div>
            </article>
          </div>

          <div v-else-if="stepIndex === 2" class="space-y-5">
            <div>
              <h3 class="text-xl font-semibold text-n-slate-12">
                {{ $t('JRC_CAMPAIGNS.WIZARD.MESSAGES_TITLE') }}
              </h3>
              <p class="mt-1 text-sm text-n-slate-10">
                {{ $t('JRC_CAMPAIGNS.WIZARD.MESSAGES_SUBTITLE') }}
              </p>
            </div>
            <div
              class="rounded-2xl border border-n-amber-7 bg-n-amber-2 p-4 text-sm text-n-amber-11"
            >
              <span class="i-lucide-shield-check mr-2 inline-block size-4" />{{
                $t('JRC_CAMPAIGNS.WIZARD.COMPLIANCE')
              }}
            </div>
            <div class="grid gap-4 xl:grid-cols-12">
              <aside class="rounded-2xl border border-n-weak p-4 xl:col-span-3">
                <div class="flex items-center justify-between">
                  <h4 class="text-sm font-semibold text-n-slate-12">
                    {{ $t('JRC_CAMPAIGNS.WIZARD.SEQUENCE') }}
                  </h4>
                  <span
                    class="rounded-full bg-n-alpha-2 px-2 py-1 text-[10px] text-n-slate-10"
                    >{{ form.steps.length }}</span
                  >
                </div>
                <div class="mt-4 space-y-2">
                  <template
                    v-for="(message, index) in form.steps"
                    :key="message.id || index"
                  >
                    <button
                      type="button"
                      class="w-full rounded-xl border p-3 text-left"
                      :class="
                        activeMessageIndex === index
                          ? 'border-n-brand bg-n-brand/5'
                          : 'border-n-weak'
                      "
                      @click="activeMessageIndex = index"
                    >
                      <div class="flex items-start gap-2">
                        <span
                          class="flex size-6 shrink-0 items-center justify-center rounded-full bg-n-brand text-[10px] font-semibold text-white"
                          >{{ index + 1 }}</span
                        ><span class="min-w-0 flex-1"
                          ><span
                            class="block text-xs font-semibold text-n-slate-12"
                            >{{ messageTypeLabel(message.kind) }}</span
                          ><span
                            class="mt-1 block truncate text-[11px] text-n-slate-9"
                            >{{
                              message.template_name ||
                              message.file_name ||
                              message.body ||
                              $t('JRC_CAMPAIGNS.WIZARD.MESSAGE_NOT_CONFIGURED')
                            }}</span
                          ></span
                        >
                      </div>
                    </button>
                    <div
                      v-if="index < form.steps.length - 1"
                      class="flex items-center justify-center gap-2 py-1 text-[10px] text-n-slate-9"
                    >
                      <span class="h-4 w-px bg-n-weak" /><span
                        v-if="message.delay_after_seconds"
                        >{{
                          $t('JRC_CAMPAIGNS.WIZARD.WAIT_SECONDS', {
                            value: message.delay_after_seconds,
                          })
                        }}</span
                      >
                    </div>
                  </template>
                </div>
                <button
                  type="button"
                  class="mt-3 flex w-full items-center justify-center gap-2 rounded-xl border border-dashed border-n-brand px-3 py-2.5 text-xs font-medium text-n-brand"
                  @click="addMessage"
                >
                  <span class="i-lucide-plus size-4" />{{
                    $t('JRC_CAMPAIGNS.WIZARD.ADD_MESSAGE')
                  }}
                </button>
              </aside>
              <article
                v-if="activeMessage"
                class="rounded-2xl border border-n-weak p-5 xl:col-span-5"
              >
                <div class="flex items-center justify-between gap-3">
                  <h4 class="text-sm font-semibold text-n-slate-12">
                    {{
                      $t('JRC_CAMPAIGNS.WIZARD.MESSAGE_NUMBER', {
                        number: activeMessageIndex + 1,
                      })
                    }}
                  </h4>
                  <div class="flex gap-1">
                    <button
                      type="button"
                      class="rounded-lg p-2 text-n-slate-10 hover:bg-n-alpha-2"
                      :disabled="activeMessageIndex === 0"
                      :title="$t('JRC_CAMPAIGNS.WIZARD.MOVE_UP')"
                      @click="moveMessage(activeMessageIndex, -1)"
                    >
                      <span class="i-lucide-arrow-up size-4" /></button
                    ><button
                      type="button"
                      class="rounded-lg p-2 text-n-slate-10 hover:bg-n-alpha-2"
                      :disabled="activeMessageIndex === form.steps.length - 1"
                      :title="$t('JRC_CAMPAIGNS.WIZARD.MOVE_DOWN')"
                      @click="moveMessage(activeMessageIndex, 1)"
                    >
                      <span class="i-lucide-arrow-down size-4" /></button
                    ><button
                      v-if="form.steps.length > 1"
                      type="button"
                      class="rounded-lg p-2 text-n-ruby-11 hover:bg-n-ruby-3"
                      :title="$t('JRC_CAMPAIGNS.WIZARD.REMOVE_MESSAGE')"
                      @click="removeMessage(activeMessageIndex)"
                    >
                      <span class="i-lucide-trash-2 size-4" />
                    </button>
                  </div>
                </div>
                <div class="mt-4 grid grid-cols-2 gap-3">
                  <label class="text-xs font-medium text-n-slate-10"
                    >{{ $t('JRC_CAMPAIGNS.WIZARD.TYPE')
                    }}<select
                      v-model="activeMessage.kind"
                      class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-background px-3 py-2.5 text-sm"
                    >
                      <option value="template">
                        {{ $t('JRC_CAMPAIGNS.WIZARD.TEMPLATE') }}
                      </option>
                      <option value="text">
                        {{ $t('JRC_CAMPAIGNS.WIZARD.TEXT') }}
                      </option>
                      <option value="image">
                        {{ $t('JRC_CAMPAIGNS.WIZARD.IMAGE') }}
                      </option>
                      <option value="document">
                        {{ $t('JRC_CAMPAIGNS.WIZARD.DOCUMENT') }}
                      </option>
                      <option value="video">
                        {{ $t('JRC_CAMPAIGNS.WIZARD.VIDEO') }}
                      </option>
                      <option value="audio">
                        {{ $t('JRC_CAMPAIGNS.WIZARD.AUDIO') }}
                      </option>
                    </select></label
                  ><label class="text-xs font-medium text-n-slate-10"
                    >{{ $t('JRC_CAMPAIGNS.WIZARD.DELAY_AFTER')
                    }}<input
                      v-model.number="activeMessage.delay_after_seconds"
                      type="number"
                      min="0"
                      class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-background px-3 py-2.5 text-sm"
                  /></label>
                </div>
                <div
                  v-if="activeMessage.kind === 'template'"
                  class="mt-4 space-y-4"
                >
                  <div class="grid gap-3 sm:grid-cols-2">
                    <label class="text-xs font-medium text-n-slate-10"
                      >{{ $t('JRC_CAMPAIGNS.WIZARD.TEMPLATE_NAME')
                      }}<select
                        :value="`${activeMessage.template_name}::${activeMessage.template_language}`"
                        class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-background px-3 py-2.5 text-sm"
                        @change="
                          selectTemplate(activeMessage, $event.target.value)
                        "
                      >
                        <option value="::">
                          {{ $t('JRC_CAMPAIGNS.WIZARD.SELECT_OPTION') }}
                        </option>
                        <option
                          v-for="template in templates"
                          :key="`${template.name}-${template.language}`"
                          :value="`${template.name}::${template.language}`"
                        >
                          {{ template.name }} · {{ template.language }}
                        </option>
                      </select></label
                    ><label class="text-xs font-medium text-n-slate-10"
                      >{{ $t('JRC_CAMPAIGNS.WIZARD.TEMPLATE_LANGUAGE')
                      }}<input
                        v-model="activeMessage.template_language"
                        class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-background px-3 py-2.5 text-sm"
                    /></label>
                  </div>
                  <div
                    v-if="variablesForMessage(activeMessage).length"
                    class="rounded-xl bg-n-alpha-1 p-4"
                  >
                    <h5
                      class="text-xs font-semibold uppercase tracking-wide text-n-slate-10"
                    >
                      {{ $t('JRC_CAMPAIGNS.WIZARD.VARIABLES') }}
                    </h5>
                    <div class="mt-3 space-y-3">
                      <div
                        v-for="variable in variablesForMessage(activeMessage)"
                        :key="variable"
                        class="grid gap-2 sm:grid-cols-[90px_1fr]"
                      >
                        <span
                          class="rounded-lg bg-n-background px-2 py-2 text-center font-mono text-xs text-n-brand"
                          >{{ variableToken(variable) }}</span
                        >
                        <div>
                          <select
                            v-model="activeMessage.variableMappings[variable]"
                            class="w-full rounded-xl border border-n-weak bg-n-background px-3 py-2 text-sm"
                          >
                            <option
                              v-for="option in mappingOptions"
                              :key="option.value"
                              :value="option.value"
                            >
                              {{ option.label }}
                            </option></select
                          ><input
                            v-if="
                              activeMessage.variableMappings[variable] ===
                              '__custom__'
                            "
                            v-model="activeMessage.variableValues[variable]"
                            class="mt-2 w-full rounded-xl border border-n-weak bg-n-background px-3 py-2 text-sm"
                            :placeholder="
                              $t(
                                'JRC_CAMPAIGNS.WIZARD.VARIABLE_CUSTOM_PLACEHOLDER'
                              )
                            "
                          />
                        </div>
                      </div>
                    </div>
                  </div>
                  <button
                    type="button"
                    class="text-xs font-medium text-n-slate-10 hover:text-n-brand"
                    @click="syncAdvancedParams(activeMessage)"
                  >
                    <span class="i-lucide-code-2 mr-1 inline-block size-3" />{{
                      $t('JRC_CAMPAIGNS.WIZARD.ADVANCED_SETTINGS')
                    }}</button
                  ><label
                    v-if="activeMessage.advancedOpen"
                    class="block text-xs font-medium text-n-slate-10"
                    >{{ $t('JRC_CAMPAIGNS.WIZARD.TEMPLATE_PARAMS')
                    }}<textarea
                      v-model="activeMessage.templateParamsText"
                      rows="6"
                      class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-background px-3 py-2 font-mono text-xs"
                    />
                  </label>
                </div>
                <label
                  v-else-if="activeMessage.kind === 'text'"
                  class="mt-4 block text-xs font-medium text-n-slate-10"
                  >{{ $t('JRC_CAMPAIGNS.WIZARD.BODY')
                  }}<textarea
                    v-model="activeMessage.body"
                    rows="7"
                    class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-background px-3 py-2.5 text-sm"
                    :placeholder="$t('JRC_CAMPAIGNS.WIZARD.BODY_PLACEHOLDER')"
                  /><span class="mt-1 block font-normal text-n-slate-9">{{
                    $t('JRC_CAMPAIGNS.WIZARD.SPINTAX_HELP')
                  }}</span></label
                >
                <div v-else class="mt-4 space-y-3">
                  <label class="block text-xs font-medium text-n-slate-10"
                    >{{ $t('JRC_CAMPAIGNS.WIZARD.MEDIA')
                    }}<input
                      type="file"
                      class="mt-1.5 block w-full rounded-xl border border-n-weak bg-n-background px-3 py-2 text-sm"
                      @change="
                        uploadMedia($event, activeMessage, activeMessageIndex)
                      "
                    /><span
                      v-if="uploadingStep === activeMessageIndex"
                      class="mt-1 block text-xs text-n-slate-9"
                      >{{ $t('JRC_CAMPAIGNS.WIZARD.UPLOADING') }}</span
                    ><span
                      v-else-if="activeMessage.file_name"
                      class="mt-1 block text-xs text-n-slate-9"
                      >{{ activeMessage.file_name }}</span
                    ></label
                  ><label class="block text-xs font-medium text-n-slate-10"
                    >{{ $t('JRC_CAMPAIGNS.WIZARD.MEDIA_URL')
                    }}<input
                      v-model="activeMessage.media_url"
                      class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-background px-3 py-2.5 text-sm" /></label
                  ><label class="block text-xs font-medium text-n-slate-10"
                    >{{ $t('JRC_CAMPAIGNS.WIZARD.BODY')
                    }}<textarea
                      v-model="activeMessage.body"
                      rows="3"
                      class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-background px-3 py-2.5 text-sm"
                    />
                  </label>
                </div>
                <div class="mt-4 rounded-xl border border-n-weak p-3">
                  <label
                    class="flex items-center gap-2 text-xs font-medium text-n-slate-12"
                    ><input
                      v-model="activeMessage.only_if_no_reply"
                      type="checkbox"
                    />{{
                      $t('JRC_CAMPAIGNS.WIZARD.FOLLOW_UP_ONLY_NO_REPLY')
                    }}</label
                  ><label
                    v-if="activeMessage.only_if_no_reply"
                    class="mt-3 block text-xs font-medium text-n-slate-10"
                    >{{ $t('JRC_CAMPAIGNS.WIZARD.FOLLOW_UP_HOURS')
                    }}<input
                      v-model.number="activeMessage.follow_up_after_hours"
                      type="number"
                      min="1"
                      class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-background px-3 py-2 text-sm"
                  /></label>
                </div>
                <div
                  v-if="selectedSendingInboxes.length > 1"
                  class="mt-4 rounded-xl border border-dashed border-n-weak p-3"
                >
                  <p class="mb-3 text-xs font-medium text-n-slate-12">
                    {{
                      $t(
                        activeMessage.kind === 'template'
                          ? 'JRC_CAMPAIGNS.WIZARD.PER_INBOX_TEMPLATE'
                          : 'JRC_CAMPAIGNS.WIZARD.PER_INBOX_MESSAGE'
                      )
                    }}
                  </p>
                  <label
                    v-for="inbox in selectedSendingInboxes"
                    :key="inbox.id"
                    class="mb-3 block text-xs font-medium text-n-slate-10 last:mb-0"
                    >{{ inbox.name
                    }}<select
                      v-if="activeMessage.kind === 'template'"
                      :value="
                        activeMessage.inbox_overrides?.[inbox.id]?.template_name
                          ? `${activeMessage.inbox_overrides[inbox.id].template_name}::${activeMessage.inbox_overrides[inbox.id].template_language}`
                          : '::'
                      "
                      class="mt-1 w-full rounded-xl border border-n-weak bg-n-background px-3 py-2 text-sm"
                      @change="
                        selectInboxTemplate(
                          activeMessage,
                          inbox,
                          $event.target.value
                        )
                      "
                    >
                      <option value="::">
                        {{ $t('JRC_CAMPAIGNS.WIZARD.USE_DEFAULT_TEMPLATE') }}
                      </option>
                      <option
                        v-for="template in inbox.templates || []"
                        :key="`${inbox.id}-${template.name}-${template.language}`"
                        :value="`${template.name}::${template.language}`"
                      >
                        {{ template.name }} · {{ template.language }}
                      </option></select
                    ><textarea
                      v-else
                      :value="
                        activeMessage.inbox_overrides?.[inbox.id]?.body || ''
                      "
                      rows="2"
                      class="mt-1 w-full rounded-xl border border-n-weak bg-n-background px-3 py-2 text-sm"
                      @input="
                        activeMessage.inbox_overrides = {
                          ...activeMessage.inbox_overrides,
                          [inbox.id]: {
                            ...(activeMessage.inbox_overrides?.[inbox.id] ||
                              {}),
                            body: $event.target.value,
                          },
                        }
                      "
                    />
                  </label>
                </div>
              </article>
              <aside class="space-y-4 xl:col-span-4">
                <article class="rounded-2xl border border-n-weak p-4">
                  <h4 class="text-sm font-semibold text-n-slate-12">
                    {{ $t('JRC_CAMPAIGNS.WIZARD.WHATSAPP_PREVIEW') }}
                  </h4>
                  <div
                    class="mx-auto mt-4 max-w-sm overflow-hidden rounded-[28px] border-4 border-n-slate-12 bg-n-slate-12 p-1 shadow-lg"
                  >
                    <div class="overflow-hidden rounded-[22px] bg-[#e9e3d7]">
                      <div
                        class="flex items-center gap-2 bg-[#075e54] px-4 py-3 text-white"
                      >
                        <span
                          class="flex size-8 items-center justify-center rounded-full bg-white/20"
                          ><span class="i-lucide-user size-4" /></span
                        ><span class="text-xs font-medium">{{
                          $t('JRC_CAMPAIGNS.WIZARD.PREVIEW_CLIENT')
                        }}</span>
                      </div>
                      <div class="min-h-56 p-4">
                        <div
                          class="ml-auto max-w-[90%] rounded-xl rounded-tr-sm bg-[#dcf8c6] p-3 text-sm text-slate-800 shadow-sm"
                        >
                          <p class="whitespace-pre-wrap leading-5">
                            {{ previewText(activeMessage) }}
                          </p>
                          <p class="mt-2 text-right text-[10px] text-slate-500">
                            {{ $t('JRC_CAMPAIGNS.WIZARD.PREVIEW_NOW') }}
                            <span class="text-sky-600">{{
                              $t('JRC_CAMPAIGNS.WIZARD.READ_RECEIPT')
                            }}</span>
                          </p>
                        </div>
                      </div>
                    </div>
                  </div>
                </article>
                <article class="rounded-2xl border border-n-weak p-4">
                  <h4 class="text-sm font-semibold text-n-slate-12">
                    {{ $t('JRC_CAMPAIGNS.WIZARD.MESSAGE_TEST') }}
                  </h4>
                  <p class="mt-1 text-xs text-n-slate-10">
                    {{ $t('JRC_CAMPAIGNS.WIZARD.MESSAGE_TEST_HELP') }}
                  </p>
                  <input
                    v-model="testPhone"
                    class="mt-3 w-full rounded-xl border border-n-weak bg-n-background px-3 py-2.5 text-sm"
                    :placeholder="
                      $t('JRC_CAMPAIGNS.WIZARD.TEST_PHONE_PLACEHOLDER')
                    "
                  />
                  <div class="mt-3 grid grid-cols-2 gap-2">
                    <button
                      type="button"
                      class="rounded-xl border border-n-strong px-3 py-2 text-xs font-medium text-n-slate-11"
                      @click="validateMessage(activeMessage)"
                    >
                      {{ $t('JRC_CAMPAIGNS.WIZARD.TEST_MESSAGE') }}</button
                    ><button
                      type="button"
                      class="rounded-xl bg-n-brand px-3 py-2 text-xs font-medium text-white disabled:opacity-50"
                      :disabled="testSending"
                      @click="sendTest(activeMessage)"
                    >
                      {{ $t('JRC_CAMPAIGNS.WIZARD.SEND_TEST') }}
                    </button>
                  </div>
                </article>
              </aside>
            </div>
          </div>

          <div v-else class="space-y-5">
            <div class="flex flex-wrap items-start justify-between gap-3">
              <div>
                <h3 class="text-xl font-semibold text-n-slate-12">
                  {{ $t('JRC_CAMPAIGNS.WIZARD.REVIEW_TITLE') }}
                </h3>
                <p class="mt-1 text-sm text-n-slate-10">
                  {{ $t('JRC_CAMPAIGNS.WIZARD.REVIEW_SUBTITLE') }}
                </p>
              </div>
              <button
                type="button"
                class="rounded-xl border border-n-brand px-3 py-2 text-xs font-medium text-n-brand"
                @click="sendTest()"
              >
                <span class="i-lucide-send mr-1 inline-block size-3" />{{
                  $t('JRC_CAMPAIGNS.WIZARD.SEND_TEST')
                }}
              </button>
            </div>
            <div class="grid gap-4 xl:grid-cols-3">
              <article
                v-for="card in [
                  {
                    icon: 'i-lucide-users-round',
                    title: $t('JRC_CAMPAIGNS.WIZARD.REVIEW_CONTACTS'),
                    lines: [
                      audienceDescription,
                      $t('JRC_CAMPAIGNS.WIZARD.REVIEW_ELIGIBLE', {
                        count: formatNumber(eligibleCount),
                      }),
                    ],
                  },
                  {
                    icon: 'i-lucide-sliders-horizontal',
                    title: $t('JRC_CAMPAIGNS.WIZARD.REVIEW_CONFIG'),
                    lines: [
                      $t('JRC_CAMPAIGNS.WIZARD.REVIEW_BOXES', {
                        count: form.inboxLinks.length,
                      }),
                      $t('JRC_CAMPAIGNS.WIZARD.REVIEW_INTERVAL', {
                        min: form.delay_min_seconds,
                        max: form.delay_max_seconds,
                      }),
                      `${form.sending_window.start}–${form.sending_window.end} · ${selectedDaysLabel}`,
                    ],
                  },
                  {
                    icon: 'i-lucide-messages-square',
                    title: $t('JRC_CAMPAIGNS.WIZARD.REVIEW_MESSAGES'),
                    lines: [
                      $t('JRC_CAMPAIGNS.WIZARD.REVIEW_SEQUENCE', {
                        count: form.steps.length,
                      }),
                      ...form.steps.map(
                        (message, index) =>
                          `${index + 1}. ${messageTypeLabel(message.kind)} — ${message.template_name || message.file_name || message.body}`
                      ),
                    ],
                  },
                ]"
                :key="card.title"
                class="rounded-2xl border border-n-weak p-5"
              >
                <div class="flex items-center gap-2">
                  <span
                    class="flex size-8 items-center justify-center rounded-xl bg-n-blue-3 text-n-blue-11"
                  >
                    <span class="size-4" :class="[card.icon]" />
                  </span>
                  <h4 class="text-sm font-semibold text-n-slate-12">
                    {{ card.title }}
                  </h4>
                </div>
                <div class="mt-4 space-y-2">
                  <p
                    v-for="line in card.lines"
                    :key="line"
                    class="text-xs leading-5 text-n-slate-10"
                  >
                    {{ line || $t('JRC_CAMPAIGNS.NOT_AVAILABLE') }}
                  </p>
                </div>
              </article>
            </div>
            <div class="grid gap-4 xl:grid-cols-2">
              <article
                class="rounded-2xl border border-n-blue-5 bg-n-blue-2 p-5"
              >
                <h4 class="text-sm font-semibold text-n-slate-12">
                  {{ $t('JRC_CAMPAIGNS.WIZARD.DISPATCH_ESTIMATE') }}
                </h4>
                <div class="mt-4 grid grid-cols-2 gap-4 sm:grid-cols-3">
                  <div
                    v-for="item in [
                      {
                        label: $t('JRC_CAMPAIGNS.WIZARD.ELIGIBLE'),
                        value: formatNumber(eligibleCount),
                      },
                      {
                        label: $t('JRC_CAMPAIGNS.WIZARD.PLANNED_MESSAGES'),
                        value: formatNumber(estimatedMessageCount),
                      },
                      {
                        label: $t('JRC_CAMPAIGNS.WIZARD.ESTIMATED_RATE'),
                        value: rateRange,
                      },
                      {
                        label: $t('JRC_CAMPAIGNS.WIZARD.ESTIMATED_DURATION'),
                        value: durationLabel,
                      },
                      {
                        label: $t('JRC_CAMPAIGNS.WIZARD.WINDOW'),
                        value: `${form.sending_window.start}–${form.sending_window.end}`,
                      },
                      {
                        label: $t('JRC_CAMPAIGNS.WIZARD.TRIGGER'),
                        value: $t(
                          `JRC_CAMPAIGNS.WIZARD.${form.trigger_type.toUpperCase()}`
                        ),
                      },
                    ]"
                    :key="item.label"
                  >
                    <p class="text-[11px] text-n-blue-11">{{ item.label }}</p>
                    <p class="mt-1 text-sm font-semibold text-n-slate-12">
                      {{ item.value }}
                    </p>
                  </div>
                </div>
              </article>
              <article
                class="rounded-2xl border p-5"
                :class="
                  hasCriticalErrors
                    ? 'border-n-ruby-6 bg-n-ruby-2'
                    : 'border-n-amber-6 bg-n-amber-2'
                "
              >
                <h4 class="text-sm font-semibold text-n-slate-12">
                  <span
                    class="i-lucide-triangle-alert mr-2 inline-block size-4 text-n-amber-11"
                  />{{ $t('JRC_CAMPAIGNS.WIZARD.ATTENTION') }}
                </h4>
                <div class="mt-4 space-y-3">
                  <div
                    v-for="item in preflightItems"
                    :key="item.text"
                    class="flex gap-2 text-xs leading-5"
                    :class="
                      item.severity === 'error'
                        ? 'text-n-ruby-11'
                        : item.severity === 'success'
                          ? 'text-n-teal-11'
                          : 'text-n-amber-11'
                    "
                  >
                    <span
                      :class="
                        item.severity === 'error'
                          ? 'i-lucide-circle-x'
                          : item.severity === 'success'
                            ? 'i-lucide-circle-check'
                            : 'i-lucide-triangle-alert'
                      "
                      class="mt-0.5 size-4 shrink-0"
                    /><span>{{ item.text }}</span>
                  </div>
                </div>
              </article>
            </div>
            <article class="rounded-2xl border border-n-weak p-5">
              <h4 class="text-sm font-semibold text-n-slate-12">
                {{ $t('JRC_CAMPAIGNS.WIZARD.MESSAGE_TEST') }}
              </h4>
              <div class="mt-3 flex flex-wrap gap-3">
                <input
                  v-model="testPhone"
                  class="min-w-64 flex-1 rounded-xl border border-n-weak bg-n-background px-3 py-2.5 text-sm"
                  :placeholder="
                    $t('JRC_CAMPAIGNS.WIZARD.TEST_PHONE_PLACEHOLDER')
                  "
                /><button
                  type="button"
                  class="rounded-xl border border-n-brand px-4 py-2.5 text-sm font-medium text-n-brand disabled:opacity-50"
                  :disabled="testSending"
                  @click="sendTest()"
                >
                  {{ $t('JRC_CAMPAIGNS.WIZARD.SEND_TEST') }}
                </button>
              </div>
            </article>
          </div>
        </section>

        <aside class="lg:col-span-3">
          <div class="space-y-4 lg:sticky lg:top-0">
            <article
              class="rounded-2xl border border-n-weak bg-n-background p-5 shadow-sm"
            >
              <p
                class="text-xs font-semibold uppercase tracking-wide text-n-slate-10"
              >
                {{ $t('JRC_CAMPAIGNS.WIZARD.SUMMARY_TITLE') }}
              </p>
              <h3 class="mt-2 truncate text-base font-semibold text-n-slate-12">
                {{ form.name || $t('JRC_CAMPAIGNS.WIZARD.UNTITLED') }}
              </h3>
              <div class="mt-5 space-y-4">
                <div
                  v-for="item in [
                    {
                      icon: 'i-lucide-users-round',
                      label: $t('JRC_CAMPAIGNS.WIZARD.REVIEW_CONTACTS'),
                      value:
                        audiencePreview.estimated_recipients === null
                          ? $t('JRC_CAMPAIGNS.WIZARD.CALCULATING')
                          : $t('JRC_CAMPAIGNS.WIZARD.SUMMARY_ELIGIBLE', {
                              count: formatNumber(eligibleCount),
                            }),
                    },
                    {
                      icon: 'i-lucide-message-circle',
                      label: $t('JRC_CAMPAIGNS.FILTERS.CHANNEL'),
                      value: $t('JRC_CAMPAIGNS.CHANNEL_WHATSAPP'),
                    },
                    {
                      icon: 'i-lucide-inbox',
                      label: $t('JRC_CAMPAIGNS.WIZARD.REVIEW_INBOXES'),
                      value: $t('JRC_CAMPAIGNS.WIZARD.SUMMARY_SELECTED', {
                        count: form.inboxLinks.length,
                      }),
                    },
                    {
                      icon: 'i-lucide-messages-square',
                      label: $t('JRC_CAMPAIGNS.WIZARD.REVIEW_MESSAGES'),
                      value: $t('JRC_CAMPAIGNS.WIZARD.SUMMARY_CONFIGURED', {
                        count: form.steps.filter(messageValid).length,
                      }),
                    },
                    {
                      icon: 'i-lucide-clock-3',
                      label: $t('JRC_CAMPAIGNS.WIZARD.ESTIMATED_DURATION'),
                      value: durationLabel,
                    },
                  ]"
                  :key="item.label"
                  class="flex gap-3"
                >
                  <span
                    class="flex size-8 shrink-0 items-center justify-center rounded-xl bg-n-alpha-2 text-n-slate-10"
                  >
                    <span class="size-4" :class="[item.icon]" />
                  </span>
                  <div>
                    <p class="text-[11px] text-n-slate-9">{{ item.label }}</p>
                    <p class="mt-0.5 text-sm font-medium text-n-slate-12">
                      {{ item.value }}
                    </p>
                  </div>
                </div>
              </div>
              <div
                class="mt-5 flex items-center gap-2 rounded-xl p-3 text-xs font-medium"
                :class="
                  hasCriticalErrors
                    ? 'bg-n-ruby-3 text-n-ruby-11'
                    : 'bg-n-teal-3 text-n-teal-11'
                "
              >
                <span
                  :class="
                    hasCriticalErrors
                      ? 'i-lucide-circle-alert'
                      : 'i-lucide-circle-check'
                  "
                  class="size-4"
                />{{
                  $t(
                    hasCriticalErrors
                      ? 'JRC_CAMPAIGNS.WIZARD.SUMMARY_PENDING'
                      : 'JRC_CAMPAIGNS.WIZARD.SUMMARY_READY'
                  )
                }}
              </div>
            </article>
            <article
              class="rounded-2xl border border-n-violet-5 bg-n-violet-2 p-5"
            >
              <div class="flex items-center gap-2">
                <span
                  class="flex size-9 items-center justify-center rounded-xl bg-n-violet-4 text-n-violet-11"
                  ><span class="i-lucide-bot size-5"
                /></span>
                <div>
                  <p class="text-sm font-semibold text-n-slate-12">
                    {{ $t('JRC_CAMPAIGNS.JARVIS.TITLE') }}
                  </p>
                  <p class="text-[11px] text-n-slate-9">
                    {{ $t('JRC_CAMPAIGNS.JARVIS.SUBTITLE') }}
                  </p>
                </div>
              </div>
              <p class="mt-4 text-sm leading-6 text-n-slate-11">
                {{ jarvisMessage }}
              </p>
            </article>
          </div>
        </aside>
      </div>
    </main>

    <footer
      class="flex items-center justify-between gap-3 border-t border-n-weak bg-n-background px-5 py-4 lg:px-8"
    >
      <button
        type="button"
        class="rounded-xl border border-n-strong px-4 py-2.5 text-sm text-n-slate-12 disabled:opacity-40"
        :disabled="stepIndex === 0"
        @click="stepIndex -= 1"
      >
        {{ $t('JRC_CAMPAIGNS.WIZARD.BACK') }}
      </button>
      <div class="flex flex-wrap justify-end gap-2">
        <button
          v-if="stepIndex === 3"
          type="button"
          class="rounded-xl border border-n-strong px-4 py-2.5 text-sm font-medium text-n-slate-12 disabled:opacity-40"
          :disabled="saving"
          @click="save(false)"
        >
          {{
            $t(campaign ? 'JRC_CAMPAIGNS.SAVE_CHANGES' : 'JRC_CAMPAIGNS.SAVE')
          }}</button
        ><button
          v-if="stepIndex < 3"
          type="button"
          class="rounded-xl bg-n-brand px-5 py-2.5 text-sm font-medium text-white disabled:opacity-40"
          :disabled="!currentStepValid || previewingAudience"
          @click="nextStep"
        >
          {{ $t('JRC_CAMPAIGNS.WIZARD.NEXT') }}
          <span class="i-lucide-arrow-right ml-1 inline-block size-4" /></button
        ><button
          v-else-if="!campaign || campaign.status === 'draft'"
          type="button"
          class="rounded-xl bg-n-teal-10 px-5 py-2.5 text-sm font-medium text-white disabled:opacity-40"
          :disabled="saving || hasCriticalErrors"
          @click="save(true)"
        >
          <span class="i-lucide-rocket mr-1 inline-block size-4" />{{
            $t('JRC_CAMPAIGNS.GOVERNANCE.SAVE_FOR_REVIEW')
          }}
        </button>
      </div>
    </footer>
  </div>
</template>
