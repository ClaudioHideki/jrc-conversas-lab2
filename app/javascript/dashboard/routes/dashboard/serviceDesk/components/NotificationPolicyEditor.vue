<script setup>
import Button from 'dashboard/components-next/button/Button.vue';
import Panel from './ServiceDeskPanel.vue';
import State from './ServiceDeskState.vue';
import ScopeBar from './ScopeBar.vue';
import ServiceDeskStepper from './ServiceDeskStepper.vue';
import { NOTIFICATION_STEPS, nextStep } from '../helpers/presentationSteps';
import LookupSelect from './LookupSelect.vue';
import ServiceDefinitionSelect from './ServiceDefinitionSelect.vue';
import { useNotificationPolicy } from '../composables/useNotificationPolicy';
const props = defineProps({
  initialUnitId: { type: String, default: '' },
  initialServiceId: { type: String, default: '' },
});
const emit = defineEmits(['busyChange']);
const {
  t,
  step,
  publicationUncertain,
  labels,
  values,
  allowed,
  unitId,
  operatorId,
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
  latest,
  load,
  selectPolicy,
  saveDraft,
  restoreDraft,
  publish,
} = useNotificationPolicy(
  {
    get initialUnitId() {
      return props.initialUnitId;
    },
    get initialServiceId() {
      return props.initialServiceId;
    },
  },
  (event, value) => {
    if (event === 'busyChange') emit('busyChange', value);
  }
);
</script>

<template>
  <div class="contents">
    <Panel v-if="allowed" class="mt-4" :title="labels.notification_policies">
      <p class="text-sm text-n-slate-11">{{ labels.default_off }}</p>
      <ScopeBar
        v-model:unit-id="unitId"
        v-model:operator-id="operatorId"
        required
        :disabled="locked"
      />
      <State v-if="loading" status="loading" compact />
      <div
        v-if="!loading && unitId && currentPolicies.length"
        class="mt-4 grid gap-2"
      >
        <h3 class="text-sm font-semibold">
          {{ t('JRC_SERVICE_DESK.REDESIGN_AUTOMATIONS.published_policies') }}
        </h3>
        <button
          v-for="row in currentPolicies"
          :key="row.id"
          type="button"
          class="flex flex-wrap items-center gap-3 rounded-lg border border-n-weak p-3 text-start text-xs hover:bg-n-slate-2 focus-visible:ring-2 focus-visible:ring-n-blue-9"
          :disabled="locked"
          @click="selectPolicy(row)"
        >
          <span class="min-w-0 flex-1 font-medium">{{
            labels.events[row.event_type]
          }}</span>
          <span>{{ values.channel[row.channel] }}</span>
          <span :class="row.enabled ? 'text-n-teal-11' : 'text-n-slate-11'">{{
            t(
              row.enabled
                ? 'JRC_SERVICE_DESK.REDESIGN_AUTOMATIONS.active'
                : 'JRC_SERVICE_DESK.REDESIGN_AUTOMATIONS.inactive'
            )
          }}</span>
          <span>{{
            t('JRC_SERVICE_DESK.LIFECYCLE.version', { version: row.version })
          }}</span>
          <span
            class="i-lucide-pencil size-3 text-n-slate-11"
            aria-hidden="true"
          />
        </button>
      </div>
      <p
        v-else-if="!loading && unitId && events.length"
        class="mt-4 text-sm text-n-slate-11"
      >
        {{ t('JRC_SERVICE_DESK.REDESIGN_AUTOMATIONS.no_policies') }}
      </p>
      <section
        v-if="unitId && events.length && !loading"
        class="grid gap-4 mt-4"
      >
        <ServiceDeskStepper
          v-model="step"
          :steps="NOTIFICATION_STEPS"
          label-root="JRC_SERVICE_DESK.REFINEMENT.notification.steps"
          :label="t('JRC_SERVICE_DESK.R2.notification_policies')"
          :disabled="locked"
        />
        <div class="grid gap-4 xl:grid-cols-[minmax(0,2fr)_minmax(15rem,1fr)]">
          <div
            class="min-w-0 grid content-start gap-4 rounded-xl border border-n-weak p-4"
          >
            <template v-if="step === 'general'">
              <label class="grid gap-1 text-sm"
                >{{ labels.event_type }}
                <select
                  v-model="eventType"
                  :disabled="locked"
                  class="rounded-lg border border-n-weak bg-n-solid-1 p-2"
                >
                  <option v-for="event in events" :key="event" :value="event">
                    {{ labels.events[event] }}
                  </option>
                </select>
              </label>
              <label class="text-sm"
                ><input v-model="enabled" type="checkbox" :disabled="locked" />
                {{ labels.enabled }}</label
              >
              <p class="text-xs text-n-slate-11">{{ labels.default_off }}</p>
            </template>
            <template v-else-if="step === 'conditions'">
              <p class="text-xs text-n-slate-11">
                {{
                  t('JRC_SERVICE_DESK.REFINEMENT.notification.conditions_hint')
                }}
              </p>
              <LookupSelect
                v-model="ticketTypeId"
                resource="ticket_types"
                :unit-id="unitId"
                :disabled="locked"
                :label="t('JRC_SERVICE_DESK.FIELDS.ticket_type')"
              />
              <ServiceDefinitionSelect
                v-model="serviceId"
                :unit-id="unitId"
                :disabled="locked"
              />
            </template>
            <template v-else-if="step === 'channels'">
              <label class="grid gap-1 text-sm"
                >{{ labels.channel }}
                <select
                  v-model="channel"
                  :disabled="locked"
                  class="rounded-lg border border-n-weak bg-n-solid-1 p-2"
                >
                  <option
                    v-for="value in ['email', 'whatsapp']"
                    :key="value"
                    :value="value"
                  >
                    {{ values.channel[value] }}
                  </option>
                </select>
              </label>
              <label class="grid gap-1 text-sm"
                >{{ labels.inbox }}
                <select
                  v-model="inboxId"
                  :disabled="locked"
                  class="rounded-lg border border-n-weak bg-n-solid-1 p-2"
                >
                  <option value="">
                    {{ t('JRC_SERVICE_DESK.COMMON.select') }}
                  </option>
                  <option
                    v-for="inbox in permittedInboxes"
                    :key="inbox.id"
                    :value="inbox.id"
                  >
                    {{ inbox.name }}
                  </option>
                </select>
              </label>
              <p
                v-if="!permittedInboxes.length"
                class="text-xs text-n-slate-11"
              >
                {{ t('JRC_SERVICE_DESK.REDESIGN_AUTOMATIONS.no_inboxes') }}
              </p>
            </template>
            <template v-else-if="step === 'message'">
              <label class="grid gap-1 text-sm"
                >{{ labels.template }}
                <textarea
                  v-model="template"
                  maxlength="10000"
                  rows="9"
                  :disabled="locked"
                  class="w-full rounded-lg border border-n-weak bg-n-solid-1 p-3"
                />
              </label>
              <label class="grid gap-1 text-sm"
                >{{ labels.template_version }}
                <input
                  v-model="templateVersion"
                  maxlength="80"
                  :disabled="locked"
                  class="rounded-lg border border-n-weak bg-n-solid-1 p-2"
                />
              </label>
              <p class="text-xs font-medium">
                {{ t('JRC_SERVICE_DESK.REFINEMENT.notification.variables') }}
              </p>
              <div class="flex flex-wrap gap-1">
                <Button
                  v-for="token in tokens"
                  :key="token"
                  size="xs"
                  variant="outline"
                  :label="token"
                  :disabled="
                    locked || template.length + token.length + 4 > 10000
                  "
                  @click="template += '{{' + token + '}}'"
                />
              </div>
            </template>
            <template v-else-if="step === 'preview'">
              <p class="text-sm">
                {{
                  t('JRC_SERVICE_DESK.EXPERIENCE.notification_preview_notice')
                }}
              </p>
              <Button
                :disabled="
                  locked || !template.trim() || invalidTokens.length > 0
                "
                :label="
                  t('JRC_SERVICE_DESK.REDESIGN_AUTOMATIONS.test_template')
                "
                @click="previewed = true"
              />
              <p v-if="previewed" class="text-xs text-n-slate-11">
                {{ t('JRC_SERVICE_DESK.REDESIGN_AUTOMATIONS.example_notice') }}
              </p>
            </template>
            <template v-else>
              <h4 class="font-semibold text-sm">
                {{ t('JRC_SERVICE_DESK.REFINEMENT.notification.review') }}
              </h4>
              <p class="text-sm">
                {{ labels.events[eventType] }} / {{ values.channel[channel] }}
              </p>
              <p class="text-xs">
                {{
                  t('JRC_SERVICE_DESK.LIFECYCLE.version', {
                    version: latest?.version || 0,
                  })
                }}
              </p>
              <p class="text-xs text-n-slate-11">
                {{ t('JRC_SERVICE_DESK.REFINEMENT.notification.publish_hint') }}
              </p>
              <label class="text-sm"
                ><input
                  v-model="confirmed"
                  type="checkbox"
                  :disabled="locked"
                />
                {{ labels.confirm_policy }}</label
              >
              <p
                v-if="!template.trim() || !templateVersion.trim()"
                role="alert"
                class="text-xs text-n-amber-11"
              >
                {{
                  t('JRC_SERVICE_DESK.REFINEMENT.notification.required_message')
                }}
              </p>
            </template>
            <p
              v-if="invalidTokens.length"
              role="alert"
              class="text-xs text-n-ruby-11"
            >
              {{
                t('JRC_SERVICE_DESK.REDESIGN_AUTOMATIONS.invalid_tokens', {
                  tokens: invalidTokens.join(', '),
                })
              }}
            </p>
          </div>
          <aside
            class="min-w-0 grid content-start gap-3 rounded-xl border border-n-weak bg-n-solid-1 p-4"
            aria-live="polite"
          >
            <h4 class="text-sm font-semibold">
              {{ t('JRC_SERVICE_DESK.EXPERIENCE.notification_preview') }}
            </h4>
            <p class="text-xs text-n-slate-11">
              {{ t('JRC_SERVICE_DESK.EXPERIENCE.notification_preview_notice') }}
            </p>
            <p class="text-sm">
              {{ labels.events[eventType] }} / {{ values.channel[channel] }}
            </p>
            <pre
              class="whitespace-pre-wrap break-words rounded-xl bg-n-slate-2 p-3 text-sm"
              >{{
                (previewed ? examplePreview : template) ||
                t('JRC_SERVICE_DESK.COMMON.no_value')
              }}</pre
            >
            <p class="text-xs">
              {{ labels.template_version }}:
              {{ templateVersion || t('JRC_SERVICE_DESK.COMMON.no_value') }}
            </p>
          </aside>
        </div>
        <p v-if="draftFeedback" role="status" class="text-xs text-n-slate-11">
          {{ t(`JRC_SERVICE_DESK.REDESIGN_AUTOMATIONS.${draftFeedback}`) }}
        </p>
        <footer
          class="flex flex-wrap justify-between gap-2 border-t border-n-weak pt-4"
        >
          <div class="flex flex-wrap gap-2">
            <Button
              variant="outline"
              :disabled="locked || step === NOTIFICATION_STEPS[0]"
              :label="t('JRC_SERVICE_DESK.REFINEMENT.back')"
              @click="step = nextStep(NOTIFICATION_STEPS, step, -1)"
            />
            <Button
              variant="ghost"
              :disabled="locked"
              :label="t('JRC_SERVICE_DESK.REDESIGN_AUTOMATIONS.save_draft')"
              @click="saveDraft"
            />
            <Button
              variant="ghost"
              :disabled="locked"
              :label="t('JRC_SERVICE_DESK.REDESIGN_AUTOMATIONS.restore_draft')"
              @click="restoreDraft"
            />
          </div>
          <Button
            v-if="step !== 'review'"
            :disabled="locked"
            :label="t('JRC_SERVICE_DESK.COMMON.next')"
            @click="step = nextStep(NOTIFICATION_STEPS, step, 1)"
          />
          <Button
            v-else
            :disabled="
              locked ||
              !confirmed ||
              !template.trim() ||
              !templateVersion.trim() ||
              invalidTokens.length > 0 ||
              (enabled && !permittedInboxes.some(row => row.id === inboxId))
            "
            :label="labels.save_policy"
            @click="publish"
          />
          <Button
            v-if="publicationUncertain"
            variant="outline"
            :disabled="locked"
            :label="t('JRC_SERVICE_DESK.COMMON.refresh')"
            @click="load"
          />
        </footer>
      </section>
      <Button
        v-if="feedback === 'unavailable'"
        type="button"
        variant="outline"
        class="mt-3"
        :disabled="busy || loading"
        :label="t('JRC_SERVICE_DESK.COMMON.retry')"
        @click="load"
      />
      <p v-if="feedback" role="status" class="text-sm">
        {{ labels[feedback] }}
      </p>
    </Panel>
  </div>
</template>
