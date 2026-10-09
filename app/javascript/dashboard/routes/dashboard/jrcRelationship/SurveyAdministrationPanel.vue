<script setup>
import { ref, computed, watch, onBeforeUnmount } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcRelationship';
import { buttonClass, inputClass, message } from './definitions';
import SurveyRuleTemplatePanel from './SurveyRuleTemplatePanel.vue';
const props = defineProps({
  allowed: Boolean,
  metadata: { type: Object, default: () => ({}) },
});
const route = useRoute();
const store = useStore();
const { t } = useI18n();
const tab = ref('definitions');
const definitions = ref([]);
const rules = ref([]);
const origins = ref([]);
const record = ref(null);
const history = ref([]);
const decisions = ref([]);
const originIndex = ref('');
const preview = ref(null);
const busy = ref(false);
const error = ref('');
const tabs = [
  'definitions',
  'questions',
  'rules',
  'history',
  'preview',
  'decisions',
];
let generation = 0;
let controller;
const rows = computed(() =>
  tab.value === 'rules' ? rules.value : definitions.value
);
const recordKind = computed(() =>
  tab.value === 'rules' ? 'rules' : 'definitions'
);
const label = key => t(`RELATIONSHIP.SURVEY_ADMIN.${key}`);
const templateSummary = settings => {
  const template = settings.whatsapp_template.template_params;
  return [template.name, template.language, template.category].join(' · ');
};
const copy = value => JSON.parse(JSON.stringify(value));
const load = async () => {
  generation += 1;
  const version = generation;
  controller?.abort();
  controller = new AbortController();
  definitions.value = [];
  rules.value = [];
  origins.value = [];
  record.value = null;
  history.value = [];
  preview.value = null;
  decisions.value = [];
  error.value = '';
  busy.value = false;
  originIndex.value = '';
  if (!props.allowed) return;
  busy.value = true;
  try {
    const result = await Promise.all([
      API.surveyDefinitions(route.params.accountId, {
        signal: controller.signal,
      }),
      API.surveyRules(route.params.accountId, { signal: controller.signal }),
      API.surveyOrigins(route.params.accountId, { signal: controller.signal }),
    ]);
    if (version !== generation) return;
    [definitions.value, rules.value, origins.value] = result.map(
      response => response.data.payload
    );
  } catch (err) {
    if (version === generation && err.code !== 'ERR_CANCELED')
      error.value = message(err);
  } finally {
    if (version === generation) busy.value = false;
  }
};
const mutate = async operation => {
  if (busy.value || !props.allowed) return;
  const version = generation;
  busy.value = true;
  error.value = '';
  try {
    await operation();
    if (version === generation) await load();
  } catch (err) {
    if (version === generation) error.value = message(err);
  } finally {
    if (version === generation) busy.value = false;
  }
};
const addQuestion = () =>
  record.value.questions.push({
    key: `question_${record.value.questions.length + 1}`,
    text: '',
    type: 'text',
    required: false,
  });
const resetScale = () => {
  if (record.value.kind === 'ces')
    record.value.settings.ces_direction ||= 'higher_is_better';
  else delete record.value.settings.ces_direction;
  const scale = record.value.kind === 'csat' ? [1, 5] : [0, 10];
  record.value.questions[0] = {
    ...record.value.questions[0],
    type: 'scale',
    min: scale[0],
    max: scale[1],
    required: true,
  };
};
const edit = row => {
  if (row) {
    record.value = copy(row);
    ['available_from', 'available_until'].forEach(key => {
      if (!record.value.settings[key]) return;
      const value = new Date(record.value.settings[key]);
      record.value.settings[key] = new Date(
        value.getTime() - value.getTimezoneOffset() * 60000
      )
        .toISOString()
        .slice(0, 16);
    });
    return;
  }
  record.value =
    recordKind.value === 'definitions'
      ? {
          name: '',
          code: '',
          kind: 'nps',
          status: 'draft',
          questions: [
            {
              key: 'rating',
              text: '',
              type: 'scale',
              min: 0,
              max: 10,
              required: true,
            },
          ],
          settings: {
            recovery_enabled: false,
            recovery_sla_hours: 24,
            thank_you: '',
          },
        }
      : {
          name: '',
          definition_id: '',
          execution_member_id: '',
          active: false,
          priority: 0,
          matchers: {},
          settings: {
            channel: 'public_link',
            delivery_inbox_id: null,
            whatsapp_template: null,
            frequency_days: 30,
            frequency_scope: 'contact_type',
            delay_minutes: 0,
            expires_hours: 168,
            max_attempts: 1,
            resend_minutes: 60,
            consent_required: true,
          },
        };
};
const save = () => {
  const payload = copy(record.value);
  if (recordKind.value === 'definitions') {
    ['available_from', 'available_until'].forEach(key => {
      if (payload.settings[key])
        payload.settings[key] = new Date(payload.settings[key]).toISOString();
      else delete payload.settings[key];
    });
    if (payload.settings.low_threshold === '')
      delete payload.settings.low_threshold;
  }
  if (recordKind.value === 'rules')
    payload.matchers = Object.fromEntries(
      Object.entries(payload.matchers).filter(
        ([, value]) => value !== '' && value !== null
      )
    );
  return mutate(() =>
    API.saveSurveyConfiguration(
      route.params.accountId,
      recordKind.value,
      payload
    )
  );
};
const duplicate = row =>
  mutate(() =>
    API.duplicateSurveyConfiguration(
      route.params.accountId,
      recordKind.value,
      row.id,
      recordKind.value === 'definitions'
        ? `${row.code.slice(0, 45)}_${crypto.randomUUID().slice(0, 8)}`
        : undefined
    )
  );
const inspect = async (kind, row) => {
  const version = generation;
  error.value = '';
  try {
    const { data } = await API.surveyConfigurationHistory(
      route.params.accountId,
      kind,
      row.id
    );
    if (version === generation) history.value = data.payload;
  } catch (err) {
    if (version === generation) error.value = message(err);
  }
};
const simulate = async () => {
  const selected = origins.value[Number(originIndex.value)];
  if (!selected || originIndex.value === '' || busy.value) return;
  const version = generation;
  busy.value = true;
  error.value = '';
  const fields = {
    source_type: selected.type,
    source_id: selected.id,
    cycle_key: 'administrative-preview',
  };
  try {
    const { data } = await (tab.value === 'decisions'
      ? API.surveyDecisions(route.params.accountId, fields)
      : API.previewSurveyPolicy(route.params.accountId, fields));
    if (version !== generation) return;
    if (tab.value === 'decisions') decisions.value = data.payload;
    else preview.value = data;
  } catch (err) {
    if (version === generation) error.value = message(err);
  } finally {
    if (version === generation) busy.value = false;
  }
};
const references = computed(() => ({
  company_id: props.metadata.survey_companies,
  unit_id: props.metadata.survey_units,
  team_id: props.metadata.teams,
  inbox_id: props.metadata.survey_inboxes,
  product_id: props.metadata.products,
  contract_id: props.metadata.survey_contracts,
}));
watch(
  [
    () => route.params.accountId,
    () => store.getters.getCurrentUserID,
    () => props.allowed,
  ],
  load,
  { immediate: true }
);
watch(tab, () => {
  record.value = null;
  history.value = [];
  preview.value = null;
  decisions.value = [];
});
onBeforeUnmount(() => {
  generation += 1;
  controller?.abort();
});
</script>

<template>
  <p
    v-if="!allowed"
    role="status"
  >
    {{ t('RELATIONSHIP.RESTRICTED') }}
  </p>
  <section
    v-else
    class="space-y-4"
  >
    <p class="rounded-lg bg-n-solid-2 p-3 text-sm">
      {{ label('OFF_GUIDANCE') }}
    </p>
    <nav
      class="flex flex-wrap gap-2"
      :aria-label="label('NAVIGATION')"
    >
      <button
        v-for="item in tabs"
        :key="item"
        type="button"
        :class="buttonClass"
        :aria-pressed="tab === item"
        @click="tab = item"
      >
        {{ label(item) }}
      </button>
    </nav>
    <p
      v-if="busy"
      role="status"
    >
      {{ t('RELATIONSHIP.LOADING') }}
    </p>
    <p
      v-if="error"
      role="alert"
    >
      {{ error }}
    </p>
    <template v-if="['definitions', 'questions', 'rules'].includes(tab)">
      <button
        type="button"
        :class="buttonClass"
        :disabled="busy"
        data-testid="new-survey-config"
        @click="edit(null)"
      >
        {{ t('RELATIONSHIP.NEW') }}
      </button>
      <ul class="divide-y divide-n-weak">
        <li
          v-for="row in rows"
          :key="row.id"
          class="flex flex-wrap items-center gap-2 py-3"
        >
          <span class="flex-1"
            >{{ row.name }} ·
            {{ t('RELATIONSHIP.VERSION', { version: row.version }) }} ·
            {{
              row.status
                ? t(`RELATIONSHIP.STATES.${row.status}`)
                : t(row.active ? 'RELATIONSHIP.YES' : 'RELATIONSHIP.NO')
            }}</span
          >
          <button
            type="button"
            :class="buttonClass"
            @click="edit(row)"
          >
            {{ t('RELATIONSHIP.EDIT') }}
          </button>
          <button
            type="button"
            :class="buttonClass"
            :disabled="busy"
            @click="duplicate(row)"
          >
            {{ label('DUPLICATE') }}
          </button>
        </li>
      </ul>
      <form
        v-if="record"
        class="space-y-3 rounded-xl border border-n-weak p-4"
        data-testid="survey-config-form"
        @submit.prevent="save"
      >
        <label class="block"
          >{{ label('NAME')
          }}<input
            v-model="record.name"
            required
            maxlength="120"
            :class="inputClass"
            data-testid="survey-name"
        /></label>
        <template v-if="recordKind === 'definitions'">
          <label class="block"
            >{{ label('CODE')
            }}<input
              v-model="record.code"
              required
              pattern="[a-z0-9_-]{1,60}"
              maxlength="60"
              :class="inputClass"
          /></label>
          <label class="block"
            >{{ label('TYPE')
            }}<select
              v-model="record.kind"
              :class="inputClass"
              @change="resetScale"
            >
              <option
                v-for="kind in ['nps', 'csat', 'ces', 'custom']"
                :key="kind"
                :value="kind"
              >
                {{ label(kind) }}
              </option>
            </select></label
          >
          <label class="block"
            >{{ t('RELATIONSHIP.FIELDS.status')
            }}<select
              v-model="record.status"
              :class="inputClass"
            >
              <option
                v-for="status in ['draft', 'active', 'archived']"
                :key="status"
                :value="status"
              >
                {{ t(`RELATIONSHIP.STATES.${status}`) }}
              </option>
            </select></label
          >
          <fieldset
            v-for="(question, index) in record.questions"
            :key="index"
            class="space-y-2 rounded-lg border border-n-weak p-3"
          >
            <legend>{{ label('QUESTION') }} {{ index + 1 }}</legend>
            <label class="block"
              >{{ label('CODE')
              }}<input
                v-model="question.key"
                required
                pattern="[a-z0-9_-]{1,60}"
                :class="inputClass"
            /></label>
            <label class="block"
              >{{ label('TEXT')
              }}<textarea
                v-model="question.text"
                required
                maxlength="1000"
                :class="inputClass"
              />
            </label>
            <label class="block"
              >{{ label('FORMAT')
              }}<select
                v-model="question.type"
                :class="inputClass"
                :disabled="index === 0 && record.kind !== 'custom'"
                @change="
                  question.options =
                    question.type === 'choice'
                      ? [{ value: 'option_1', label: '' }]
                      : undefined;
                  question.min = 0;
                  question.max = 10;
                "
              >
                <option
                  v-for="type in ['scale', 'text', 'choice']"
                  :key="type"
                  :value="type"
                >
                  {{ label(type) }}
                </option>
              </select></label
            >
            <div
              v-if="question.type === 'scale'"
              class="flex gap-3"
            >
              <label
                >{{ label('MIN')
                }}<input
                  v-model.number="question.min"
                  type="number"
                  min="0"
                  max="99"
                  required
                  :class="inputClass"
                  :disabled="index === 0 && record.kind !== 'custom'" /></label
              ><label
                >{{ label('MAX')
                }}<input
                  v-model.number="question.max"
                  type="number"
                  min="1"
                  max="100"
                  required
                  :class="inputClass"
                  :disabled="index === 0 && record.kind !== 'custom'"
              /></label>
            </div>
            <template v-if="question.type === 'choice'"
              ><div
                v-for="(option, optionIndex) in question.options"
                :key="optionIndex"
                class="flex gap-2"
              >
                <label
                  >{{ label('CODE')
                  }}<input
                    v-model="option.value"
                    required
                    maxlength="60"
                    :class="inputClass" /></label
                ><label
                  >{{ label('TEXT')
                  }}<input
                    v-model="option.label"
                    required
                    maxlength="120"
                    :class="inputClass" /></label
                ><button
                  type="button"
                  :class="buttonClass"
                  @click="question.options.splice(optionIndex, 1)"
                >
                  {{ t('RELATIONSHIP.REMOVE_ITEM') }}
                </button>
              </div>
              <button
                type="button"
                :class="buttonClass"
                :disabled="question.options.length >= 30"
                @click="
                  question.options.push({
                    value: `option_${question.options.length + 1}`,
                    label: '',
                  })
                "
              >
                {{ t('RELATIONSHIP.ADD_ITEM') }}
              </button></template
            >
            <label
              ><input
                v-model="question.required"
                type="checkbox"
              />
              {{ label('REQUIRED') }}</label
            >
            <label
              v-if="index > 0"
              class="block"
              ><input
                type="checkbox"
                :checked="!!question.condition"
                @change="
                  question.condition = $event.target.checked
                    ? {
                        question: record.questions[0].key,
                        operator: 'eq',
                        value: '',
                      }
                    : undefined
                "
              />
              {{ label('CONDITIONAL') }}</label
            >
            <div
              v-if="question.condition"
              class="flex gap-2"
            >
              <select
                v-model="question.condition.question"
                :class="inputClass"
              >
                <option
                  v-for="previous in record.questions.slice(0, index)"
                  :key="previous.key"
                  :value="previous.key"
                >
                  {{ previous.text || previous.key }}
                </option></select
              ><select
                v-model="question.condition.operator"
                :class="inputClass"
              >
                <option
                  v-for="operator in ['eq', 'lte', 'gte']"
                  :key="operator"
                  :value="operator"
                >
                  {{ t(`RELATIONSHIP.OPERATORS.${operator}`) }}
                </option></select
              ><input
                v-model="question.condition.value"
                required
                :class="inputClass"
                :aria-label="label('VALUE')"
              />
            </div>
            <button
              v-if="index > 0"
              type="button"
              :class="buttonClass"
              @click="record.questions.splice(index, 1)"
            >
              {{ t('RELATIONSHIP.REMOVE_ITEM') }}
            </button>
          </fieldset>
          <button
            type="button"
            :class="buttonClass"
            :disabled="record.questions.length >= 20"
            @click="addQuestion"
          >
            {{ t('RELATIONSHIP.ADD_ITEM') }}
          </button>
          <label class="block"
            ><input
              v-model="record.settings.recovery_enabled"
              type="checkbox"
            />
            {{ label('RECOVERY') }}</label
          >
          <label
            v-if="record.kind === 'ces'"
            class="block"
          >
            {{ label('CES_DIRECTION') }}
            <select
              v-model="record.settings.ces_direction"
              :class="inputClass"
              data-testid="ces-direction"
            >
              <option value="higher_is_better">
                {{ label('higher_is_better') }}
              </option>
              <option value="lower_is_better">
                {{ label('lower_is_better') }}
              </option>
            </select>
          </label>
          <label
            v-if="['ces', 'csat'].includes(record.kind)"
            class="block"
            >{{ label('LOW_THRESHOLD') }}
            <input
              v-model.number="record.settings.low_threshold"
              type="number"
              min="0"
              max="100"
              :class="inputClass"
            />
          </label>
          <label
            v-for="key in ['available_from', 'available_until']"
            :key="key"
            class="block"
          >
            {{ label(key)
            }}<input
              v-model="record.settings[key]"
              type="datetime-local"
              :class="inputClass"
            />
          </label>
          <label class="block"
            >{{ label('RECOVERY_HOURS')
            }}<input
              v-model.number="record.settings.recovery_sla_hours"
              type="number"
              min="1"
              max="8760"
              :class="inputClass"
          /></label>
          <label class="block"
            >{{ label('THANK_YOU')
            }}<textarea
              v-model="record.settings.thank_you"
              maxlength="1000"
              :class="inputClass"
            />
          </label>
        </template>
        <template v-else>
          <label class="block"
            >{{ label('MODEL')
            }}<select
              v-model="record.definition_id"
              required
              :class="inputClass"
            >
              <option value="">{{ t('RELATIONSHIP.SELECT') }}</option>
              <option
                v-for="definition in definitions"
                :key="definition.id"
                :value="definition.id"
              >
                {{ definition.name }}
              </option>
            </select></label
          >
          <label class="block"
            >{{ label('EXECUTOR')
            }}<select
              v-model="record.execution_member_id"
              :class="inputClass"
              data-testid="survey-rule-executor"
            >
              <option value="">{{ t('RELATIONSHIP.SELECT') }}</option>
              <option
                v-for="member in metadata.execution_members || []"
                :key="member[0]"
                :value="member[0]"
              >
                {{ member[1] }}
              </option>
            </select></label
          >
          <label class="block"
            ><input
              v-model="record.active"
              type="checkbox"
              data-testid="survey-rule-active"
            />
            {{ label('RULE_ACTIVE') }}</label
          >
          <label class="block"
            >{{ t('RELATIONSHIP.FIELDS.priority')
            }}<input
              v-model.number="record.priority"
              type="number"
              min="0"
              max="1000"
              :class="inputClass"
          /></label>
          <label class="block"
            >{{ label('ORIGIN')
            }}<select
              v-model="record.matchers.source_type"
              :class="inputClass"
            >
              <option value="">{{ label('ALL') }}</option>
              <option
                v-for="type in [
                  'Conversation',
                  'JrcServiceDesk::Ticket',
                  'JrcRelationship::Qbr',
                  'JrcCrm::Activity',
                  'Call',
                ]"
                :key="type"
                :value="type"
              >
                {{ label(type) }}
              </option>
            </select></label
          >
          <label
            v-for="(options, key) in references"
            :key="key"
            class="block"
            >{{ label(key)
            }}<select
              v-model="record.matchers[key]"
              :class="inputClass"
            >
              <option value="">{{ label('ALL') }}</option>
              <option
                v-for="option in options || []"
                :key="option[0]"
                :value="option[0]"
              >
                {{ option[1] }}
              </option>
            </select></label
          >
          <label class="block"
            >{{ label('CHANNEL')
            }}<select
              v-model="record.settings.channel"
              :class="inputClass"
              data-testid="survey-rule-channel"
              @change="record.settings.whatsapp_template = null"
            >
              <option
                v-for="channel in ['same', 'email', 'whatsapp', 'public_link']"
                :key="channel"
                :value="channel"
              >
                {{ label(channel) }}
              </option>
            </select></label
          >
          <label
            v-if="['email', 'whatsapp'].includes(record.settings.channel)"
            class="block"
            >{{ label('DELIVERY_INBOX')
            }}<select
              v-model="record.settings.delivery_inbox_id"
              required
              :class="inputClass"
              data-testid="survey-rule-inbox"
            >
              <option :value="null">{{ t('RELATIONSHIP.SELECT') }}</option>
              <option
                v-for="inbox in metadata.survey_inboxes || []"
                :key="inbox[0]"
                :value="inbox[0]"
              >
                {{ inbox[1] }}
              </option>
            </select></label
          >
          <SurveyRuleTemplatePanel
            v-if="record.settings.channel === 'whatsapp'"
            v-model="record.settings.whatsapp_template"
            :inbox-id="record.settings.delivery_inbox_id"
            :executor-id="record.execution_member_id"
            :inboxes="metadata.survey_whatsapp_inboxes || []"
          />
          <label class="block"
            >{{ label('FREQUENCY_SCOPE')
            }}<select
              v-model="record.settings.frequency_scope"
              :class="inputClass"
            >
              <option
                v-for="scope in ['contact_type', 'contact', 'company']"
                :key="scope"
                :value="scope"
              >
                {{ label(scope) }}
              </option>
            </select></label
          >
          <label
            v-for="key in [
              'frequency_days',
              'delay_minutes',
              'expires_hours',
              'max_attempts',
              'resend_minutes',
            ]"
            :key="key"
            class="block"
            >{{ label(key)
            }}<input
              v-model.number="record.settings[key]"
              type="number"
              :min="['frequency_days', 'delay_minutes'].includes(key) ? 0 : 1"
              :max="key === 'max_attempts' ? 3 : 52560"
              :class="inputClass"
          /></label>
          <label class="block"
            ><input
              v-model="record.settings.consent_required"
              type="checkbox"
            />
            {{ label('CONSENT') }}</label
          >
        </template>
        <button
          type="submit"
          :class="buttonClass"
          :disabled="busy"
        >
          {{ t('RELATIONSHIP.SAVE') }}</button
        ><button
          type="button"
          :class="buttonClass"
          @click="record = null"
        >
          {{ t('RELATIONSHIP.CLOSE') }}
        </button>
      </form>
    </template>
    <template v-if="tab === 'history'"
      ><div
        v-for="kind in ['definitions', 'rules']"
        :key="kind"
      >
        <h3>{{ label(kind) }}</h3>
        <button
          v-for="row in kind === 'rules' ? rules : definitions"
          :key="row.id"
          type="button"
          :class="buttonClass"
          @click="inspect(kind, row)"
        >
          {{ row.name }}
        </button>
      </div>
      <details
        v-for="version in history"
        :key="version.version"
        class="rounded-lg border border-n-weak p-3"
      >
        <summary>
          {{ t('RELATIONSHIP.VERSION', { version: version.version }) }} ·
          {{ version.created_at }}
        </summary>
        <p>{{ version.payload.name }}</p>
        <p
          v-for="question in version.payload.questions || []"
          :key="question.key"
        >
          {{ question.text }} · {{ label(question.type) }} {{ question.min }}–{{
            question.max
          }}
        </p>
        <p v-if="version.payload.matchers">
          {{ label('ORIGIN') }}:
          {{ label(version.payload.matchers.source_type || 'ALL') }}
        </p>
        <p v-if="version.payload.settings?.whatsapp_template">
          {{ label('TEMPLATE.TITLE') }}:
          {{ templateSummary(version.payload.settings) }}
        </p>
      </details></template
    >
    <form
      v-if="['preview', 'decisions'].includes(tab)"
      @submit.prevent="simulate"
    >
      <p class="mb-3">{{ label('PREVIEW_GUIDANCE') }}</p>
      <label
        >{{ label('ORIGIN')
        }}<select
          v-model="originIndex"
          required
          :class="inputClass"
        >
          <option value="">{{ t('RELATIONSHIP.SELECT') }}</option>
          <option
            v-for="(origin, index) in origins"
            :key="`${origin.type}:${origin.id}`"
            :value="String(index)"
          >
            {{ label(origin.type) }} · {{ origin.label }}
          </option>
        </select></label
      ><button
        type="submit"
        :class="buttonClass"
        :disabled="busy"
      >
        {{ label(tab === 'decisions' ? 'LOAD_DECISIONS' : 'SIMULATE') }}
      </button>
    </form>
    <p
      v-if="preview"
      role="status"
    >
      {{ label(`reasons.${preview.reason}`) }} ·
      {{ preview.rule?.name || label('NO_RULE') }}
    </p>
    <ul>
      <li
        v-for="decision in decisions"
        :key="decision.id"
      >
        {{ decision.evaluated_at }} ·
        {{ label(`reasons.${decision.reason}`) }} ·
        {{
          t('RELATIONSHIP.VERSION', { version: decision.rule_version || '—' })
        }}
      </li>
    </ul>
  </section>
</template>
