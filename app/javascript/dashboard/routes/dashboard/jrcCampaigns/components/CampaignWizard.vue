<script setup>
import CampaignFilters from 'dashboard/routes/dashboard/jrcCustomers/components/CampaignFilters.vue';
import ConsentPanel from './ConsentPanel.vue';
import CampaignAudienceInput from './CampaignAudienceInput.vue';
import { useCustomerMaster } from 'dashboard/routes/dashboard/jrcCustomers/useCustomerMaster';
import {
  sourceInboxesForChannel,
  evolutionMinimumInterval,
  testResultAlert,
} from '../evolutionHelpers';
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

const props = defineProps({
  campaign: { type: Object, default: null },
  metadata: { type: Object, required: true },
  initialSanitizedListId: { type: [Number, String], default: null },
});

const emit = defineEmits([
  'close',
  'saved',
  'reviewRequested',
  'refreshSenders',
]);
const { t } = useI18n();
const { enabled: hasCustomerMaster } = useCustomerMaster();
const stepIndex = ref(0);
const saving = ref(false);
const showConsents = ref(false);
const audienceInputMode = ref(null);
const addedLists = ref([]);
const audienceLists = computed(() => [
  ...addedLists.value,
  ...(props.metadata.sanitized_lists || []).filter(
    list =>
      !addedLists.value.some(added => Number(added.id) === Number(list.id))
  ),
]);
const uploadingStep = ref(null);
const previewingAudience = ref(false);
const audiencePreview = ref({
  found_count: null,
  available_recipients: null,
  estimated_recipients: null,
  manually_excluded_count: 0,
  without_destination_count: 0,
  without_whatsapp_count: 0,
  without_email_count: 0,
  blacklisted_count: 0,
  blocked_count: 0,
  duplicate_count: 0,
  sample: [],
});
const activeMessageIndex = ref(0);
const showRecipientManager = ref(false);
const recipientManagerLoading = ref(false);
const recipientSearch = ref('');
const recipientRows = ref([]);
const recipientPagination = ref({
  page: 1,
  per_page: 50,
  total: 0,
  total_pages: 1,
});
const testDestination = ref('');
const testSending = ref(false);
const latestTest = ref(null);
const latestTestSignature = ref(null);
const newTestCoolingDown = ref(false);
let newTestTimer;
let audienceTimer;
let audienceRequest = 0;
let recipientSearchTimer;

const defaultMessage = (kind = 'template') => ({
  id: null,
  position: 0,
  kind,
  subject: '',
  body: '',
  media_url: '',
  file_name: '',
  media_asset_id: null,
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
  delivery_channel: 'whatsapp',
  audience_type: 'all_contacts',
  audience_config: {
    label_ids: [],
    inbox_ids: [],
    pipeline_id: null,
    stage_ids: [],
    sanitized_list_id: null,
    customer_filters: {},
    recipient_selection_mode: 'exclude',
    recipient_selection_keys: [],
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
  form.inboxLinks
    .filter(item => item.enabled !== false)
    .map(item => Number(item.inbox_id))
);
const isEmail = computed(() => form.delivery_channel === 'email');
const audienceSourceSignature = computed(() =>
  JSON.stringify({
    delivery_channel: form.delivery_channel,
    audience_type: form.audience_type,
    label_ids: form.audience_config.label_ids,
    inbox_ids: form.audience_config.inbox_ids,
    pipeline_id: form.audience_config.pipeline_id,
    stage_ids: form.audience_config.stage_ids,
    sanitized_list_id: form.audience_config.sanitized_list_id,
    customer_filters: form.audience_config.customer_filters,
    sending_inbox_ids: selectedInboxIds.value,
  })
);
const deliveryChannelLabel = computed(() =>
  t(
    isEmail.value
      ? 'JRC_CAMPAIGNS.CHANNEL_EMAIL'
      : 'JRC_CAMPAIGNS.CHANNEL_WHATSAPP'
  )
);
const availableSendingInboxes = computed(() =>
  isEmail.value
    ? props.metadata.email_inboxes || []
    : props.metadata.whatsapp_inboxes || props.metadata.inboxes || []
);
const availableSourceInboxes = computed(() =>
  sourceInboxesForChannel(props.metadata, isEmail.value)
);
const selectedSendingInboxes = computed(() =>
  availableSendingInboxes.value.filter(inbox =>
    selectedInboxIds.value.includes(Number(inbox.id))
  )
);
const usesEvolution = computed(() =>
  selectedSendingInboxes.value.some(inbox =>
    ['evolution', 'broker'].includes(inbox.connector)
  )
);
const usesBroker = computed(() =>
  selectedSendingInboxes.value.some(inbox => inbox.connector === 'broker')
);
const testResultTitle = computed(() =>
  usesBroker.value
    ? t('JRC_CAMPAIGNS.BROKER.TEST_RESULT')
    : t('JRC_CAMPAIGNS.EVOLUTION.TEST_RESULT')
);
const mixesWhatsAppConnectors = computed(
  () =>
    !isEmail.value &&
    usesEvolution.value &&
    new Set(
      selectedSendingInboxes.value.map(inbox => inbox.connector || 'official')
    ).size > 1
);
watch(selectedSendingInboxes, inboxes => {
  const minimum = evolutionMinimumInterval(inboxes);
  if (minimum) {
    form.delay_min_seconds = Math.max(form.delay_min_seconds, minimum);
    form.delay_max_seconds = Math.max(form.delay_max_seconds, minimum);
  }
  if (
    inboxes.some(inbox => ['evolution', 'broker'].includes(inbox.connector))
  ) {
    form.steps.forEach(message => {
      if (
        message.kind === 'template' &&
        !message.id &&
        !message.template_name &&
        !message.body
      )
        message.kind = 'text';
    });
  }
});
const testKeys = new Map();
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
    key: 'import_csv',
    label: t('JRC_CAMPAIGNS.WIZARD.SOURCE_IMPORT'),
    description: t('JRC_CAMPAIGNS.WIZARD.SOURCE_IMPORT_HELP'),
    icon: 'i-lucide-file-up',
  },
  {
    key: 'manual_numbers',
    label: t('JRC_CAMPAIGNS.WIZARD.SOURCE_MANUAL'),
    description: t('JRC_CAMPAIGNS.WIZARD.SOURCE_MANUAL_HELP'),
    icon: 'i-lucide-list-plus',
  },
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
const channelCards = computed(() => [
  {
    key: 'whatsapp',
    label: t('JRC_CAMPAIGNS.CHANNEL_WHATSAPP'),
    description: t('JRC_CAMPAIGNS.WIZARD.CHANNEL_WHATSAPP_HELP'),
    icon: 'i-lucide-message-circle',
  },
  {
    key: 'email',
    label: t('JRC_CAMPAIGNS.CHANNEL_EMAIL'),
    description: t('JRC_CAMPAIGNS.WIZARD.CHANNEL_EMAIL_HELP'),
    icon: 'i-lucide-mail',
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
    selectedInboxIds.value.length > 0 &&
    !mixesWhatsAppConnectors.value &&
    form.sending_window.days.length > 0 &&
    Number(form.delay_min_seconds) >= 0 &&
    Number(form.delay_max_seconds) >= Number(form.delay_min_seconds) &&
    (form.trigger_type !== 'scheduled' || Boolean(form.scheduled_at)) &&
    (form.recurrence_config.type !== 'custom' ||
      Number(form.recurrence_config.interval_days) > 0)
);
const messageValid = message => {
  if (message.kind === 'email')
    return Boolean(message.subject.trim() && message.body.trim());
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
const eligibleCount = computed(() =>
  Number(audiencePreview.value.estimated_recipients || 0)
);
const currentStepValid = computed(() => {
  if (stepIndex.value === 0)
    return (
      Boolean(form.name.trim()) &&
      sourceValid.value &&
      audiencePreview.value.estimated_recipients !== null &&
      eligibleCount.value > 0
    );
  if (stepIndex.value === 1) return configValid.value;
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
  if (
    sourceValid.value &&
    audiencePreview.value.estimated_recipients !== null &&
    eligibleCount.value === 0
  )
    items.push({
      severity: 'error',
      text: t('JRC_CAMPAIGNS.WIZARD.VALIDATION_RECIPIENTS'),
    });
  if (!selectedInboxIds.value.length)
    items.push({
      severity: 'error',
      text: t('JRC_CAMPAIGNS.WIZARD.VALIDATION_INBOX'),
    });
  if (mixesWhatsAppConnectors.value)
    items.push({
      severity: 'error',
      text: t('JRC_CAMPAIGNS.GUIDE.SEPARATE_SENDERS'),
    });
  if (!messagesValid.value)
    items.push({
      severity: 'error',
      text: t('JRC_CAMPAIGNS.WIZARD.VALIDATION_MESSAGE'),
    });
  if (audiencePreview.value.without_destination_count)
    items.push({
      severity: 'warning',
      text: t(
        isEmail.value
          ? 'JRC_CAMPAIGNS.WIZARD.WARNING_NO_EMAIL'
          : 'JRC_CAMPAIGNS.WIZARD.WARNING_NO_WHATSAPP',
        {
          count: formatNumber(audiencePreview.value.without_destination_count),
        }
      ),
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
  if (audiencePreview.value.manually_excluded_count)
    items.push({
      severity: 'warning',
      text: t('JRC_CAMPAIGNS.WIZARD.WARNING_MANUAL_EXCLUSIONS', {
        count: formatNumber(audiencePreview.value.manually_excluded_count),
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
const toggleArrayValue = (array, value) => {
  const index = array.findIndex(item => Number(item) === Number(value));
  if (index >= 0) array.splice(index, 1);
  else array.push(value);
};
const selectAudience = audienceType => {
  if (['import_csv', 'manual_numbers'].includes(audienceType)) {
    audienceInputMode.value = audienceType === 'import_csv' ? 'csv' : 'manual';
    form.audience_type = 'sanitized_list';
    form.audience_config.sanitized_list_id = null;
    return;
  }
  audienceInputMode.value = null;
  form.audience_type = audienceType;
};
const resetRecipientSelection = () => {
  form.audience_config.recipient_selection_mode = 'exclude';
  form.audience_config.recipient_selection_keys = [];
  audiencePreview.value = {
    ...audiencePreview.value,
    found_count: null,
    available_recipients: null,
    estimated_recipients: null,
    manually_excluded_count: 0,
    sample: [],
  };
  recipientSearch.value = '';
  recipientRows.value = [];
  recipientPagination.value = {
    page: 1,
    per_page: 50,
    total: 0,
    total_pages: 1,
  };
  showRecipientManager.value = false;
};
const updateRecipientSelection = (selectionKey, selected) => {
  const mode = form.audience_config.recipient_selection_mode;
  const keys = form.audience_config.recipient_selection_keys;
  const index = keys.indexOf(selectionKey);
  const shouldStoreKey = mode === 'include' ? selected : !selected;
  if (shouldStoreKey && index < 0) keys.push(selectionKey);
  if (!shouldStoreKey && index >= 0) keys.splice(index, 1);
};
const toggleRecipient = recipient => {
  const selected = !recipient.selected;
  updateRecipientSelection(recipient.selection_key, selected);
  recipient.selected = selected;
  const difference = selected ? 1 : -1;
  audiencePreview.value.estimated_recipients = Math.max(
    0,
    eligibleCount.value + difference
  );
  audiencePreview.value.manually_excluded_count = Math.max(
    0,
    Number(audiencePreview.value.available_recipients || 0) -
      Number(audiencePreview.value.estimated_recipients || 0)
  );
};
const setAllRecipients = selected => {
  form.audience_config.recipient_selection_mode = selected
    ? 'exclude'
    : 'include';
  form.audience_config.recipient_selection_keys = [];
  recipientRows.value.forEach(recipient => {
    recipient.selected = selected;
  });
  audiencePreview.value.estimated_recipients = selected
    ? Number(audiencePreview.value.available_recipients || 0)
    : 0;
  audiencePreview.value.manually_excluded_count = selected
    ? 0
    : Number(audiencePreview.value.available_recipients || 0);
};
const toggleSendingInbox = inbox => {
  const index = form.inboxLinks.findIndex(
    item => Number(item.inbox_id) === Number(inbox.id)
  );
  if (index >= 0 && form.inboxLinks[index].enabled === false)
    form.inboxLinks[index].enabled = true;
  else if (index >= 0) form.inboxLinks.splice(index, 1);
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
  let kind = usesEvolution.value ? 'text' : 'template';
  if (isEmail.value) kind = 'email';
  const message = defaultMessage(kind);
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
    const { data } = await JrcCampaignsAPI.uploadMedia(
      file,
      message.kind === 'email' ? 'document' : message.kind
    );
    message.media_url = data.url;
    message.file_name = data.file_name;
    message.media_asset_id = data.id;
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
  subject: message.subject,
  body: message.body,
  media_url: message.media_url,
  file_name: message.file_name,
  media_asset_id: message.media_asset_id,
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
    delivery_channel: form.delivery_channel,
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
  audienceRequest += 1;
  const request = audienceRequest;
  const sourceSignature = audienceSourceSignature.value;
  previewingAudience.value = true;
  try {
    const { data } = await JrcCampaignsAPI.audiencePreview({
      inbox_id: selectedInboxIds.value[0],
      audience_type: form.audience_type,
      delivery_channel: form.delivery_channel,
      audience_config: form.audience_config,
    });
    if (
      request === audienceRequest &&
      sourceSignature === audienceSourceSignature.value
    )
      audiencePreview.value = data;
  } catch {
    if (
      request !== audienceRequest ||
      sourceSignature !== audienceSourceSignature.value
    )
      return;
    audiencePreview.value = {
      ...audiencePreview.value,
      found_count: null,
      available_recipients: null,
      estimated_recipients: null,
      sample: [],
    };
  } finally {
    if (request === audienceRequest) previewingAudience.value = false;
  }
};
const selectCreatedList = async list => {
  addedLists.value.unshift(list);
  form.audience_type = 'sanitized_list';
  form.audience_config.sanitized_list_id = list.id;
  audienceInputMode.value = null;
  emit('refreshSenders');
  await refreshAudiencePreview();
};
const refreshRecipientManager = async () => {
  if (!sourceValid.value || !showRecipientManager.value) return;
  recipientManagerLoading.value = true;
  try {
    const { data } = await JrcCampaignsAPI.audiencePreview(
      {
        inbox_id: selectedInboxIds.value[0],
        audience_type: form.audience_type,
        delivery_channel: form.delivery_channel,
        audience_config: form.audience_config,
      },
      {
        include_recipients: true,
        recipient_search: recipientSearch.value,
        recipient_page: recipientPagination.value.page,
        recipient_per_page: recipientPagination.value.per_page,
      }
    );
    recipientRows.value = data.recipients || [];
    recipientPagination.value = data.recipient_pagination || {
      page: 1,
      per_page: 50,
      total: 0,
      total_pages: 1,
    };
  } catch {
    recipientRows.value = [];
    useAlert(t('JRC_CAMPAIGNS.ALERTS.RECIPIENTS_LOAD_FAILED'));
  } finally {
    recipientManagerLoading.value = false;
  }
};
const openRecipientManager = async () => {
  showRecipientManager.value = true;
  recipientPagination.value.page = 1;
  await refreshRecipientManager();
};
const changeRecipientPage = async page => {
  if (page < 1 || page > recipientPagination.value.total_pages) return;
  recipientPagination.value.page = page;
  await refreshRecipientManager();
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
    if (startAfterSave && !response.data.approval_valid) {
      useAlert(t('JRC_CAMPAIGNS.GOVERNANCE.REVIEW_REQUIRED'));
      emit('reviewRequested', response.data);
      return;
    }
    if (startAfterSave) await JrcCampaignsAPI.launch(response.data.id);
    useAlert(
      t(
        props.campaign
          ? 'JRC_CAMPAIGNS.ALERTS.UPDATED'
          : 'JRC_CAMPAIGNS.ALERTS.SAVED'
      )
    );
    emit('saved');
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
  if (testSending.value) return;
  if (!testDestination.value.trim()) {
    useAlert(
      t(
        isEmail.value
          ? 'JRC_CAMPAIGNS.ALERTS.TEST_EMAIL_REQUIRED'
          : 'JRC_CAMPAIGNS.ALERTS.TEST_PHONE_REQUIRED'
      )
    );
    return;
  }
  if (!message || !messageValid(message) || !form.inboxLinks.length) {
    useAlert(t('JRC_CAMPAIGNS.ALERTS.TEST_CONFIG_REQUIRED'));
    return;
  }
  const inbox = selectedSendingInboxes.value.find(
    item => Number(item.id) === Number(form.inboxLinks[0].inbox_id)
  );
  const evolution = ['evolution', 'broker'].includes(inbox?.connector);
  if (
    evolution &&
    !window.confirm(
      inbox.connector === 'broker'
        ? t('JRC_CAMPAIGNS.BROKER.CONFIRM_TEST', {
            sender: inbox.phone_number,
            recipient: testDestination.value,
          })
        : t('JRC_CAMPAIGNS.EVOLUTION.CONFIRM_TEST', {
            sender: inbox.phone_number,
            recipient: testDestination.value,
          })
    )
  )
    return;
  testSending.value = true;
  try {
    const payload = {
      delivery_channel: form.delivery_channel,
      phone_number: isEmail.value ? null : testDestination.value,
      email: isEmail.value ? testDestination.value : null,
      inbox_id: form.inboxLinks[0].inbox_id,
      step: serializeStep(message),
    };
    let signature = null;
    if (evolution) {
      signature = JSON.stringify(payload);
      if (!testKeys.has(signature))
        testKeys.set(signature, crypto.randomUUID());
      payload.idempotency_key = testKeys.get(signature);
      payload.operator_confirmed = true;
    }
    const { data } = await JrcCampaignsAPI.testMessage(payload);
    if (data.test_delivery_id) {
      latestTest.value = { ...data, id: data.test_delivery_id };
      latestTestSignature.value = signature;
      if (data.status === 'sent') {
        clearTimeout(newTestTimer);
        newTestCoolingDown.value = true;
        newTestTimer = setTimeout(
          () => {
            newTestCoolingDown.value = false;
          },
          Math.max(60, Number(inbox.min_interval_seconds) || 60) * 1000
        );
      }
    }
    useAlert(t(testResultAlert(data)));
  } catch (error) {
    useAlert(
      error?.response?.data?.errors?.join(', ') ||
        t('JRC_CAMPAIGNS.ALERTS.TEST_FAILED')
    );
  } finally {
    testSending.value = false;
  }
};
const prepareNewTest = () => {
  if (
    testSending.value ||
    newTestCoolingDown.value ||
    latestTest.value?.status !== 'sent' ||
    !latestTestSignature.value
  )
    return;
  if (!window.confirm(t('JRC_CAMPAIGNS.EVOLUTION.NEW_TEST_CONFIRM'))) return;
  testKeys.delete(latestTestSignature.value);
  latestTestSignature.value = null;
  latestTest.value = null;
};
onBeforeUnmount(() => clearTimeout(newTestTimer));
const validateMessage = message => {
  useAlert(
    t(
      messageValid(message)
        ? 'JRC_CAMPAIGNS.ALERTS.MESSAGE_VALID'
        : 'JRC_CAMPAIGNS.ALERTS.MESSAGE_INVALID'
    )
  );
};
const refreshTestResult = async () => {
  try {
    const { data } = await JrcCampaignsAPI.testDelivery(latestTest.value.id);
    latestTest.value = data;
  } catch {
    useAlert(t('JRC_CAMPAIGNS.ALERTS.ACTION_FAILED'));
  }
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
    '{{email}}':
      audiencePreview.value.sample?.[0]?.email ||
      t('JRC_CAMPAIGNS.WIZARD.PREVIEW_EMAIL'),
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
  form.delivery_channel = campaign.delivery_channel || 'whatsapp';
  form.audience_type = campaign.audience_type || 'all_contacts';
  form.audience_config = {
    label_ids: campaign.audience_config?.label_ids || [],
    inbox_ids: campaign.audience_config?.inbox_ids || [],
    pipeline_id: campaign.audience_config?.pipeline_id || null,
    stage_ids: campaign.audience_config?.stage_ids || [],
    sanitized_list_id: campaign.audience_config?.sanitized_list_id || null,
    customer_filters: campaign.audience_config?.customer_filters || {},
    recipient_selection_mode:
      campaign.audience_config?.recipient_selection_mode === 'include'
        ? 'include'
        : 'exclude',
    recipient_selection_keys:
      campaign.audience_config?.recipient_selection_keys || [],
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
  form.conversation_mode =
    form.delivery_channel === 'email' &&
    campaign.conversation_mode === 'reply_only'
      ? 'pending'
      : campaign.conversation_mode || 'reply_only';
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
    campaign.steps?.length
      ? campaign.steps
      : [
          defaultMessage(
            form.delivery_channel === 'email' ? 'email' : 'template'
          ),
        ]
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
if (!props.campaign && props.initialSanitizedListId) {
  form.audience_type = 'sanitized_list';
  form.audience_config.sanitized_list_id = props.initialSanitizedListId;
}
watch(
  () => form.delivery_channel,
  (value, previous) => {
    if (previous === undefined || value === previous) return;
    form.inboxLinks = [];
    form.audience_config.inbox_ids = [];
    form.steps = [defaultMessage(value === 'email' ? 'email' : 'template')];
    form.conversation_mode = value === 'email' ? 'pending' : 'reply_only';
    activeMessageIndex.value = 0;
    testDestination.value = '';
  }
);
watch(audienceSourceSignature, (value, previous) => {
  if (previous !== undefined && value !== previous) resetRecipientSelection();
});
watch(
  availableSendingInboxes,
  inboxes => {
    const availableIds = new Set(inboxes.map(inbox => Number(inbox.id)));
    const usableInboxes = inboxes.filter(
      inbox => inboxHealth(inbox).state !== 'error'
    );
    form.inboxLinks = form.inboxLinks.filter(item =>
      availableIds.has(Number(item.inbox_id))
    );
    if (usableInboxes.length === 1 && !form.inboxLinks.length) {
      form.inboxLinks.push({
        id: null,
        inbox_id: usableInboxes[0].id,
        weight: 1,
        position: 0,
        enabled: true,
      });
    }
  },
  { immediate: true }
);
watch(
  () => form.audience_config.pipeline_id,
  (value, previous) => {
    if (previous !== undefined && Number(value) !== Number(previous))
      form.audience_config.stage_ids = [];
  }
);
watch(
  [
    () => form.delivery_channel,
    () => form.audience_type,
    () => form.audience_config,
    () => selectedInboxIds.value,
  ],
  () => {
    window.clearTimeout(audienceTimer);
    if (!sourceValid.value) return;
    audienceTimer = window.setTimeout(refreshAudiencePreview, 450);
  },
  { deep: true }
);
watch(recipientSearch, () => {
  window.clearTimeout(recipientSearchTimer);
  recipientPagination.value.page = 1;
  recipientSearchTimer = window.setTimeout(refreshRecipientManager, 350);
});
onMounted(refreshAudiencePreview);
onBeforeUnmount(() => {
  audienceRequest += 1;
  window.clearTimeout(audienceTimer);
  window.clearTimeout(recipientSearchTimer);
});
watch(
  () => form.audience_type,
  value => {
    if (value === 'sanitized_list') form.audience_config.customer_filters = {};
  }
);
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
          <div
            v-if="latestTest"
            class="mb-4 rounded-lg border border-n-weak p-3 text-sm"
            role="status"
          >
            <span>{{ testResultTitle }}</span>
            {{
              t('JRC_CAMPAIGNS.BROKER.RESULT_STATUS', {
                id: latestTest.id,
                status: latestTest.provider_status || latestTest.status,
              })
            }}
            <p v-if="latestTest.error_message">
              {{ latestTest.error_message }}
            </p>
            <button
              type="button"
              class="mt-2 rounded-lg border border-n-strong px-3 py-2"
              @click="refreshTestResult"
            >
              {{ t('JRC_CAMPAIGNS.REFRESH') }}
            </button>
            <button
              v-if="latestTest.status === 'sent' && latestTestSignature"
              type="button"
              class="ml-2 mt-2 rounded-lg border border-n-brand px-3 py-2 text-n-brand disabled:opacity-40"
              :disabled="testSending || newTestCoolingDown"
              @click="prepareNewTest"
            >
              {{ t('JRC_CAMPAIGNS.EVOLUTION.NEW_TEST') }}
            </button>
            <p v-if="newTestCoolingDown" class="mt-2 text-n-slate-11">
              {{ t('JRC_CAMPAIGNS.EVOLUTION.WAIT_INTERVAL') }}
            </p>
          </div>
          <div v-if="stepIndex === 0" class="space-y-5">
            <section
              v-if="
                !isEmail &&
                ((!usesEvolution && selectedInboxIds.length > 0) ||
                  showConsents)
              "
              class="rounded-xl border border-n-blue-5 bg-n-blue-2 p-4"
            >
              <p class="text-sm text-n-slate-12">
                {{ t('JRC_CAMPAIGNS.GUIDE.WIZARD_CONSENT_HELP') }}
              </p>
              <button
                type="button"
                class="mt-2 text-sm font-semibold text-n-blue-11"
                :aria-expanded="showConsents"
                @click="showConsents = !showConsents"
              >
                {{ t('JRC_CAMPAIGNS.GUIDE.MANAGE_CONSENTS') }}
              </button>
              <ConsentPanel
                v-if="showConsents"
                embedded
                @changed="refreshAudiencePreview"
              />
            </section>
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
            <div class="campaign-channel-panel rounded-2xl border p-5">
              <h4 class="text-sm font-semibold text-n-slate-12">
                {{ $t('JRC_CAMPAIGNS.WIZARD.DELIVERY_CHANNEL') }}
              </h4>
              <p class="mt-1 text-xs text-n-slate-10">
                {{ $t('JRC_CAMPAIGNS.WIZARD.DELIVERY_CHANNEL_HELP') }}
              </p>
              <div class="mt-4 grid gap-3 sm:grid-cols-2">
                <button
                  v-for="channel in channelCards"
                  :key="channel.key"
                  type="button"
                  class="relative rounded-xl border p-4 text-left transition-colors"
                  :class="
                    form.delivery_channel === channel.key
                      ? 'border-n-brand bg-n-brand/5'
                      : 'border-n-weak hover:border-n-strong'
                  "
                  @click="form.delivery_channel = channel.key"
                >
                  <span
                    class="flex size-9 items-center justify-center rounded-xl bg-n-alpha-2 text-n-slate-11"
                    ><span
                      class="size-5 shrink-0"
                      :class="channel.icon"
                      aria-hidden="true"
                  /></span>
                  <span
                    class="mt-3 block text-sm font-semibold text-n-slate-12"
                  >
                    {{ channel.label }}
                  </span>
                  <span class="mt-1 block text-xs leading-5 text-n-slate-10">
                    {{ channel.description }}
                  </span>
                  <span
                    v-if="form.delivery_channel === channel.key"
                    class="i-lucide-circle-check absolute right-3 top-3 size-5 text-n-brand"
                  />
                </button>
              </div>
            </div>
            <div class="campaign-source-panel rounded-2xl border p-5">
              <h4 class="text-sm font-semibold text-n-slate-12">
                {{ $t('JRC_CAMPAIGNS.WIZARD.SOURCE') }}
              </h4>
              <div class="mt-4 grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
                <button
                  v-for="source in sourceCards.slice(0, 3)"
                  :key="source.key"
                  type="button"
                  class="relative rounded-xl border p-4 text-left transition-colors"
                  :class="
                    (audienceInputMode === 'csv' &&
                      source.key === 'import_csv') ||
                    (audienceInputMode === 'manual' &&
                      source.key === 'manual_numbers') ||
                    (!audienceInputMode && form.audience_type === source.key)
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
                    v-if="
                      (audienceInputMode === 'csv' &&
                        source.key === 'import_csv') ||
                      (audienceInputMode === 'manual' &&
                        source.key === 'manual_numbers') ||
                      (!audienceInputMode && form.audience_type === source.key)
                    "
                    class="i-lucide-circle-check absolute right-3 top-3 size-5 text-n-brand"
                  />
                </button>
              </div>
              <CampaignAudienceInput
                v-if="audienceInputMode"
                :key="audienceInputMode"
                :mode="audienceInputMode"
                :campaign-name="form.name"
                @selected="selectCreatedList"
              />
              <details class="mt-4 rounded-xl border border-n-weak p-3">
                <summary
                  class="cursor-pointer text-sm font-medium text-n-slate-11"
                >
                  {{ t('JRC_CAMPAIGNS.WIZARD.OTHER_SOURCES') }}
                </summary>
                <div class="mt-3 flex flex-wrap gap-2">
                  <button
                    v-for="source in sourceCards.slice(3)"
                    :key="source.key"
                    type="button"
                    class="rounded-lg border border-n-weak px-3 py-2 text-sm text-n-slate-12"
                    :aria-pressed="
                      !audienceInputMode && form.audience_type === source.key
                    "
                    @click="selectAudience(source.key)"
                  >
                    {{ source.label }}
                  </button>
                </div>
              </details>
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
                    v-for="inbox in availableSourceInboxes"
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
                <div
                  v-if="!availableSourceInboxes.length"
                  class="rounded-xl bg-n-alpha-2 p-4 text-sm text-n-slate-10"
                >
                  {{
                    $t('JRC_CAMPAIGNS.WIZARD.NO_SOURCE_INBOXES', {
                      channel: deliveryChannelLabel,
                    })
                  }}
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
                v-if="
                  form.audience_type === 'sanitized_list' && !audienceInputMode
                "
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
                    v-for="list in audienceLists"
                    :key="list.id"
                    :value="list.id"
                  >
                    {{ list.name }}
                  </option>
                </select></label
              >
            </div>
            <div class="campaign-preview-panel rounded-2xl border p-5">
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
              <div class="mt-4 grid gap-3 sm:grid-cols-2 xl:grid-cols-6">
                <div
                  v-for="(item, index) in [
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
                      key: 'without_destination_count',
                      label: $t(
                        isEmail
                          ? 'JRC_CAMPAIGNS.WIZARD.NO_EMAIL'
                          : 'JRC_CAMPAIGNS.WIZARD.NO_WHATSAPP'
                      ),
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
                    {
                      key: 'manually_excluded_count',
                      label: $t('JRC_CAMPAIGNS.WIZARD.MANUALLY_EXCLUDED'),
                      className: 'text-n-ruby-11',
                    },
                  ]"
                  :key="item.key"
                  class="campaign-preview-card rounded-xl border p-4"
                  :class="`campaign-preview-card-${index + 1}`"
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
              <details
                v-if="audiencePreview.rejections?.length"
                class="mt-4 max-h-48 overflow-y-auto rounded-lg border border-n-weak p-3 text-sm"
                role="status"
              >
                <summary class="cursor-pointer font-medium">
                  {{
                    t('JRC_CAMPAIGNS.WIZARD.REJECTION_SUMMARY', {
                      count: audiencePreview.rejections.length,
                    })
                  }}
                </summary>
                <p
                  v-for="rejection in audiencePreview.rejections"
                  :key="rejection.selection_key"
                  class="mt-2"
                >
                  {{
                    rejection.name || rejection.phone_number || rejection.email
                  }}
                  · {{ rejection.reason }}
                </p>
              </details>
              <button
                v-if="Number(audiencePreview.available_recipients || 0) > 0"
                type="button"
                class="mt-4 rounded-xl border border-n-brand px-3 py-2 text-xs font-medium text-n-brand"
                @click="
                  showRecipientManager
                    ? (showRecipientManager = false)
                    : openRecipientManager()
                "
              >
                {{
                  $t(
                    showRecipientManager
                      ? 'JRC_CAMPAIGNS.WIZARD.CLOSE_RECIPIENT_MANAGER'
                      : 'JRC_CAMPAIGNS.WIZARD.MANAGE_RECIPIENTS'
                  )
                }}
              </button>
              <div
                v-if="showRecipientManager"
                class="mt-4 rounded-xl border border-n-weak p-4"
              >
                <div class="flex flex-wrap items-center justify-between gap-3">
                  <div>
                    <p class="text-sm font-semibold text-n-slate-12">
                      {{ $t('JRC_CAMPAIGNS.WIZARD.RECIPIENT_MANAGER_TITLE') }}
                    </p>
                    <p class="mt-1 text-xs text-n-slate-10">
                      {{
                        $t('JRC_CAMPAIGNS.WIZARD.RECIPIENT_SELECTION_COUNT', {
                          selected: formatNumber(eligibleCount),
                          total: formatNumber(
                            audiencePreview.available_recipients
                          ),
                        })
                      }}
                    </p>
                  </div>
                  <div class="flex flex-wrap gap-2">
                    <button
                      type="button"
                      class="rounded-lg border border-n-strong px-3 py-1.5 text-xs font-medium text-n-slate-11"
                      @click="setAllRecipients(true)"
                    >
                      {{ $t('JRC_CAMPAIGNS.WIZARD.SELECT_ALL_RECIPIENTS') }}
                    </button>
                    <button
                      type="button"
                      class="rounded-lg border border-n-strong px-3 py-1.5 text-xs font-medium text-n-slate-11"
                      @click="setAllRecipients(false)"
                    >
                      {{ $t('JRC_CAMPAIGNS.WIZARD.DESELECT_ALL_RECIPIENTS') }}
                    </button>
                  </div>
                </div>
                <div class="relative mt-4">
                  <span
                    class="i-lucide-search absolute left-3 top-1/2 size-4 -translate-y-1/2 text-n-slate-9"
                  />
                  <input
                    v-model="recipientSearch"
                    type="search"
                    class="w-full rounded-xl border border-n-weak bg-n-background py-2.5 pl-9 pr-3 text-sm"
                    :placeholder="$t('JRC_CAMPAIGNS.WIZARD.SEARCH_RECIPIENTS')"
                  />
                </div>
                <div
                  class="mt-3 overflow-hidden rounded-xl border border-n-weak"
                >
                  <p
                    v-if="recipientManagerLoading"
                    class="px-3 py-6 text-center text-xs text-n-slate-10"
                  >
                    {{ $t('JRC_CAMPAIGNS.WIZARD.LOADING_RECIPIENTS') }}
                  </p>
                  <p
                    v-else-if="!recipientRows.length"
                    class="px-3 py-6 text-center text-xs text-n-slate-10"
                  >
                    {{ $t('JRC_CAMPAIGNS.WIZARD.NO_RECIPIENTS_FOUND') }}
                  </p>
                  <template v-else>
                    <label
                      v-for="contact in recipientRows"
                      :key="contact.selection_key"
                      class="flex cursor-pointer items-center gap-3 border-b border-n-weak px-3 py-2.5 text-xs last:border-b-0 hover:bg-n-alpha-1"
                    >
                      <input
                        type="checkbox"
                        :checked="contact.selected"
                        @change="toggleRecipient(contact)"
                      />
                      <span class="min-w-0 flex-1">
                        <span
                          class="block truncate font-medium text-n-slate-12"
                          >{{
                            contact.name ||
                            $t('JRC_CAMPAIGNS.WIZARD.UNNAMED_CONTACT')
                          }}</span
                        >
                        <span class="block truncate text-n-slate-10">{{
                          isEmail ? contact.email : contact.phone_number
                        }}</span>
                      </span>
                    </label>
                  </template>
                </div>
                <div
                  v-if="recipientPagination.total_pages > 1"
                  class="mt-3 flex items-center justify-between gap-3"
                >
                  <button
                    type="button"
                    class="rounded-lg border border-n-strong px-3 py-1.5 text-xs disabled:opacity-40"
                    :disabled="
                      recipientManagerLoading || recipientPagination.page <= 1
                    "
                    @click="changeRecipientPage(recipientPagination.page - 1)"
                  >
                    {{ $t('JRC_CAMPAIGNS.WIZARD.PREVIOUS_PAGE') }}
                  </button>
                  <span class="text-xs text-n-slate-10">
                    {{
                      $t('JRC_CAMPAIGNS.WIZARD.RECIPIENT_PAGE', {
                        page: recipientPagination.page,
                        total: recipientPagination.total_pages,
                      })
                    }}
                  </span>
                  <button
                    type="button"
                    class="rounded-lg border border-n-strong px-3 py-1.5 text-xs disabled:opacity-40"
                    :disabled="
                      recipientManagerLoading ||
                      recipientPagination.page >=
                        recipientPagination.total_pages
                    "
                    @click="changeRecipientPage(recipientPagination.page + 1)"
                  >
                    {{ $t('JRC_CAMPAIGNS.WIZARD.NEXT_PAGE') }}
                  </button>
                </div>
              </div>
            </div>
          </div>

          <div v-else-if="stepIndex === 1" class="space-y-5">
            <CampaignFilters
              v-if="
                hasCustomerMaster && form.audience_type !== 'sanitized_list'
              "
              v-model="form.audience_config.customer_filters"
            />
            <div>
              <h3 class="text-xl font-semibold text-n-slate-12">
                {{ $t('JRC_CAMPAIGNS.WIZARD.CONFIG_TITLE') }}
              </h3>
              <p class="mt-1 text-sm text-n-slate-10">
                {{ $t('JRC_CAMPAIGNS.WIZARD.CONFIG_SUBTITLE') }}
              </p>
              <p
                v-if="mixesWhatsAppConnectors"
                role="alert"
                class="mt-3 rounded-lg bg-n-amber-2 p-3 text-sm text-n-amber-11"
              >
                {{ t('JRC_CAMPAIGNS.GUIDE.SEPARATE_SENDERS') }}
              </p>
            </div>
            <div class="grid gap-4 xl:grid-cols-3">
              <article class="rounded-2xl border border-n-weak p-5">
                <h4 class="text-sm font-semibold text-n-slate-12">
                  {{
                    $t(
                      isEmail
                        ? 'JRC_CAMPAIGNS.WIZARD.EMAIL_SENDING_INBOXES'
                        : 'JRC_CAMPAIGNS.WIZARD.SENDING_INBOXES'
                    )
                  }}
                </h4>
                <p class="mt-1 text-xs text-n-slate-10">
                  {{ $t('JRC_CAMPAIGNS.GUIDE.SENDER_HELP') }}
                </p>
                <button
                  type="button"
                  class="mt-3 text-xs font-medium text-n-brand"
                  @click="emit('refreshSenders')"
                >
                  {{ t('JRC_CAMPAIGNS.BROKER.REFRESH_SENDERS') }}
                </button>
                <div class="mt-4 space-y-2">
                  <div
                    v-for="inbox in availableSendingInboxes"
                    :key="inbox.id"
                    class="rounded-xl border border-n-weak p-3"
                  >
                    <label class="flex items-start gap-3"
                      ><input
                        type="checkbox"
                        class="mt-1"
                        :checked="selectedInboxIds.includes(Number(inbox.id))"
                        :disabled="
                          inboxHealth(inbox).state === 'error' &&
                          !selectedInboxIds.includes(Number(inbox.id))
                        "
                        @change="toggleSendingInbox(inbox)"
                      /><span class="min-w-0 flex-1"
                        ><span
                          class="block break-words text-sm font-medium text-n-slate-12"
                          >{{ inbox.name }}</span
                        ><span
                          class="block break-words text-xs tabular-nums text-n-slate-11"
                          >{{
                            inbox.connector === 'evolution'
                              ? t('JRC_CAMPAIGNS.EVOLUTION.SENDER')
                              : ''
                          }}
                          {{ inbox.email_address || inbox.phone_number }} ·
                          {{ inbox.provider }}</span
                        ></span
                      ><span
                        class="rounded-full px-2 py-1 text-[10px] font-medium"
                        :class="inboxHealth(inbox).className"
                        >{{ inboxHealth(inbox).label }}</span
                      ></label
                    >
                    <p
                      v-if="inbox.setup_reason"
                      class="mt-2 text-xs text-n-amber-11"
                    >
                      {{ t('JRC_CAMPAIGNS.WIZARD.SENDER_UNAVAILABLE') }}
                    </p>
                    <div
                      v-if="
                        selectedInboxIds.length > 1 &&
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
                  <div
                    v-if="!availableSendingInboxes.length"
                    class="rounded-xl bg-n-amber-2 p-4 text-sm text-n-amber-11"
                  >
                    {{
                      $t('JRC_CAMPAIGNS.WIZARD.NO_SENDING_INBOXES', {
                        channel: deliveryChannelLabel,
                      })
                    }}
                  </div>
                </div>
              </article>
              <article class="rounded-2xl border border-n-weak p-5">
                <h4 class="text-sm font-semibold text-n-slate-12">
                  {{ $t('JRC_CAMPAIGNS.WIZARD.ROTATION') }}
                </h4>
                <div v-if="selectedInboxIds.length > 1" class="mt-4 space-y-2">
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
                  v-else
                  class="mt-4 rounded-xl bg-n-alpha-2 p-4 text-sm text-n-slate-10"
                >
                  {{
                    $t(
                      selectedInboxIds.length === 1
                        ? 'JRC_CAMPAIGNS.WIZARD.SINGLE_SENDING_INBOX'
                        : 'JRC_CAMPAIGNS.WIZARD.SELECT_SENDING_INBOX'
                    )
                  }}
                </div>
                <div
                  v-if="
                    selectedInboxIds.length > 1 &&
                    ['random', 'weighted'].includes(form.rotation_mode)
                  "
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
                      <option v-if="!isEmail" value="reply_only">
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
                $t(
                  isEmail
                    ? 'JRC_CAMPAIGNS.WIZARD.EMAIL_COMPLIANCE'
                    : 'JRC_CAMPAIGNS.WIZARD.COMPLIANCE'
                )
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
                              message.subject ||
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
                    }}<input
                      v-if="isEmail"
                      :value="$t('JRC_CAMPAIGNS.WIZARD.EMAIL')"
                      disabled
                      class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-alpha-1 px-3 py-2.5 text-sm"
                    /><select
                      v-else
                      v-model="activeMessage.kind"
                      class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-background px-3 py-2.5 text-sm"
                    >
                      <option value="template" :disabled="usesEvolution">
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
                  v-if="activeMessage.kind === 'email'"
                  class="mt-4 space-y-4"
                >
                  <label class="block text-xs font-medium text-n-slate-10"
                    >{{ $t('JRC_CAMPAIGNS.WIZARD.EMAIL_SUBJECT')
                    }}<input
                      v-model="activeMessage.subject"
                      class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-background px-3 py-2.5 text-sm"
                      :placeholder="
                        $t('JRC_CAMPAIGNS.WIZARD.EMAIL_SUBJECT_PLACEHOLDER')
                      "
                  /></label>
                  <label class="block text-xs font-medium text-n-slate-10"
                    >{{ $t('JRC_CAMPAIGNS.WIZARD.EMAIL_BODY')
                    }}<textarea
                      v-model="activeMessage.body"
                      rows="10"
                      class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-background px-3 py-2.5 text-sm"
                      :placeholder="$t('JRC_CAMPAIGNS.WIZARD.BODY_PLACEHOLDER')"
                    />
                  </label>
                  <label class="block text-xs font-medium text-n-slate-10"
                    >{{ $t('JRC_CAMPAIGNS.WIZARD.EMAIL_ATTACHMENT') }}
                    <input
                      type="file"
                      class="mt-1.5 block w-full rounded-xl border border-n-weak bg-n-background px-3 py-2 text-sm"
                      @change="
                        uploadMedia($event, activeMessage, activeMessageIndex)
                      "
                    />
                    <span
                      v-if="uploadingStep === activeMessageIndex"
                      class="mt-1 block text-xs text-n-slate-9"
                      >{{ $t('JRC_CAMPAIGNS.WIZARD.UPLOADING') }}</span
                    ><span
                      v-else-if="activeMessage.file_name"
                      class="mt-1 block text-xs text-n-slate-9"
                      >{{ activeMessage.file_name }}</span
                    >
                  </label>
                </div>
                <div
                  v-else-if="activeMessage.kind === 'template'"
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
                    {{
                      $t(
                        isEmail
                          ? 'JRC_CAMPAIGNS.WIZARD.EMAIL_PREVIEW'
                          : 'JRC_CAMPAIGNS.WIZARD.WHATSAPP_PREVIEW'
                      )
                    }}
                  </h4>
                  <div
                    v-if="!isEmail"
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
                  <div
                    v-else
                    class="mt-4 overflow-hidden rounded-xl border border-n-weak bg-white text-slate-800 shadow-sm"
                  >
                    <div class="border-b border-slate-200 px-4 py-3">
                      <p class="text-xs text-slate-500">
                        {{ selectedSendingInboxes[0]?.email_address || '—' }}
                      </p>
                      <p class="mt-1 font-semibold">
                        {{
                          activeMessage.subject ||
                          $t('JRC_CAMPAIGNS.WIZARD.EMAIL_NO_SUBJECT')
                        }}
                      </p>
                    </div>
                    <p
                      class="min-h-56 whitespace-pre-wrap p-4 text-sm leading-6"
                    >
                      {{ previewText(activeMessage) }}
                    </p>
                    <p
                      v-if="activeMessage.file_name"
                      class="border-t border-slate-200 px-4 py-3 text-xs text-slate-500"
                    >
                      <span
                        class="i-lucide-paperclip mr-1 inline-block size-3"
                      />
                      {{ activeMessage.file_name }}
                    </p>
                  </div>
                </article>
                <article class="rounded-2xl border border-n-weak p-4">
                  <h4 class="text-sm font-semibold text-n-slate-12">
                    {{ $t('JRC_CAMPAIGNS.WIZARD.MESSAGE_TEST') }}
                  </h4>
                  <p class="mt-1 text-xs text-n-slate-10">
                    {{ $t('JRC_CAMPAIGNS.WIZARD.MESSAGE_TEST_HELP') }}
                  </p>
                  <p v-if="usesEvolution" class="mt-2 text-xs text-n-slate-11">
                    {{ t('JRC_CAMPAIGNS.EVOLUTION.CONTINUOUS_HELP') }}
                  </p>
                  <input
                    v-model="testDestination"
                    class="mt-3 w-full rounded-xl border border-n-weak bg-n-background px-3 py-2.5 text-sm"
                    :placeholder="
                      $t(
                        isEmail
                          ? 'JRC_CAMPAIGNS.WIZARD.TEST_EMAIL_PLACEHOLDER'
                          : 'JRC_CAMPAIGNS.WIZARD.TEST_PHONE_PLACEHOLDER'
                      )
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
                      :disabled="testSending || newTestCoolingDown"
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
                class="rounded-xl border border-n-brand px-3 py-2 text-xs font-medium text-n-brand disabled:opacity-50"
                :disabled="testSending || newTestCoolingDown"
                @click="sendTest()"
              >
                <span class="i-lucide-send mr-1 inline-block size-3" />{{
                  $t('JRC_CAMPAIGNS.WIZARD.SEND_TEST')
                }}
              </button>
            </div>
            <div class="grid gap-4 xl:grid-cols-3">
              <article
                v-for="(card, index) in [
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
                      deliveryChannelLabel,
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
                          `${index + 1}. ${messageTypeLabel(message.kind)} — ${message.subject || message.template_name || message.file_name || message.body}`
                      ),
                    ],
                  },
                ]"
                :key="card.title"
                class="campaign-review-card rounded-2xl border p-5"
                :class="`campaign-review-card-${index + 1}`"
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
                <p
                  v-if="eligibleCount === 0"
                  class="mt-3 text-xs text-n-slate-12"
                >
                  {{ t('JRC_CAMPAIGNS.CONSENT_IMPORT.AUDIENCE_HELP') }}
                </p>
                <button
                  type="button"
                  class="mt-3 rounded-lg border border-n-strong px-3 py-2 text-xs text-n-slate-12 disabled:opacity-40"
                  :disabled="previewingAudience || !sourceValid"
                  @click="refreshAudiencePreview"
                >
                  {{ t('JRC_CAMPAIGNS.CONSENT_IMPORT.REFRESH') }}
                </button>
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
              <p v-if="usesEvolution" class="mt-2 text-xs text-n-slate-11">
                {{ t('JRC_CAMPAIGNS.EVOLUTION.CONTINUOUS_HELP') }}
              </p>
              <div class="mt-3 flex flex-wrap gap-3">
                <input
                  v-model="testDestination"
                  class="min-w-64 flex-1 rounded-xl border border-n-weak bg-n-background px-3 py-2.5 text-sm"
                  :placeholder="
                    $t(
                      isEmail
                        ? 'JRC_CAMPAIGNS.WIZARD.TEST_EMAIL_PLACEHOLDER'
                        : 'JRC_CAMPAIGNS.WIZARD.TEST_PHONE_PLACEHOLDER'
                    )
                  "
                /><button
                  type="button"
                  class="rounded-xl border border-n-brand px-4 py-2.5 text-sm font-medium text-n-brand disabled:opacity-50"
                  :disabled="testSending || newTestCoolingDown"
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
              class="campaign-summary-panel rounded-2xl border p-5 shadow-sm"
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
                      icon: isEmail
                        ? 'i-lucide-mail'
                        : 'i-lucide-message-circle',
                      label: $t('JRC_CAMPAIGNS.FILTERS.CHANNEL'),
                      value: deliveryChannelLabel,
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
            campaign?.approval_valid
              ? $t('JRC_CAMPAIGNS.UPDATE_START')
              : $t('JRC_CAMPAIGNS.GOVERNANCE.SAVE_FOR_REVIEW')
          }}
        </button>
      </div>
    </footer>
  </div>
</template>

<style scoped>
.campaign-channel-panel {
  background: #eff6ff !important;
  border-color: #93c5fd !important;
}
.campaign-source-panel {
  background: #f5f3ff !important;
  border-color: #c4b5fd !important;
}
.campaign-preview-panel {
  background: #ecfeff !important;
  border-color: #67e8f9 !important;
}
.campaign-preview-card-1 {
  background: #eff6ff !important;
  border-color: #93c5fd !important;
  border-top: 4px solid #2563eb !important;
}
.campaign-preview-card-2 {
  background: #ecfdf5 !important;
  border-color: #86efac !important;
  border-top: 4px solid #16a34a !important;
}
.campaign-preview-card-3 {
  background: #fff7ed !important;
  border-color: #fdba74 !important;
  border-top: 4px solid #f97316 !important;
}
.campaign-preview-card-4 {
  background: #fff1f2 !important;
  border-color: #fda4af !important;
  border-top: 4px solid #e11d48 !important;
}
.campaign-preview-card-5 {
  background: #f5f3ff !important;
  border-color: #c4b5fd !important;
  border-top: 4px solid #7c3aed !important;
}
.campaign-preview-card-6 {
  background: #fdf2f8 !important;
  border-color: #f9a8d4 !important;
  border-top: 4px solid #ec4899 !important;
}
.campaign-review-card-1 {
  background: #eff6ff !important;
  border-color: #93c5fd !important;
  border-top: 4px solid #2563eb !important;
}
.campaign-review-card-2 {
  background: #ecfdf5 !important;
  border-color: #86efac !important;
  border-top: 4px solid #16a34a !important;
}
.campaign-review-card-3 {
  background: #f5f3ff !important;
  border-color: #c4b5fd !important;
  border-top: 4px solid #7c3aed !important;
}
.campaign-summary-panel {
  background: #fff7ed !important;
  border-color: #fdba74 !important;
  border-top: 4px solid #f97316 !important;
}
</style>
