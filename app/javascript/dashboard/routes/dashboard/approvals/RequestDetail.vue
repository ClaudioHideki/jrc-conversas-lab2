<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { decisionChoices, scopeLabel } from './model';
const props = defineProps({
  request: { type: Object, required: true },
  context: { type: Object, default: null },
  busy: Boolean,
  auditAllowed: Boolean,
});
const emit = defineEmits(['decide', 'audit']);
const { t } = useI18n();
const reason = ref('');
const choices = computed(() => decisionChoices(props.request));
</script>

<template>
  <section class="space-y-5">
    <h2 class="text-xl font-semibold">
      {{ t('JRC_APPROVALS.request') }} #{{ request.id }}
    </h2>
    <p class="text-sm">
      {{ scopeLabel(context, request) || t('JRC_APPROVALS.groupScope') }}
    </p>
    <dl
      class="grid gap-3 rounded-xl border border-n-weak bg-n-solid-2 p-4 sm:grid-cols-2"
    >
      <div
        v-for="field in [
          'resource_type',
          'resource_id',
          'requester_name',
          'policy_name',
          'policy_version',
          'issuer_company_id',
          'business_unit_id',
          'state',
          'expires_at',
          'cycle',
        ]"
        :key="field"
      >
        <dt class="text-xs text-n-slate-11">
          {{ t(`JRC_APPROVALS.${field}`) }}
        </dt>
        <dd class="break-words text-sm">{{ request[field] ?? '—' }}</dd>
      </div>
    </dl>
    <div class="space-y-2">
      <h3 class="font-semibold">{{ t('JRC_APPROVALS.steps') }}</h3>
      <p
        v-for="step in request.stages || []"
        :key="step.code"
        class="rounded-lg border border-n-weak p-3 text-sm"
      >
        {{ step.code }} · {{ step.approved_count }}/{{ step.quorum }}
      </p>
    </div>
    <section class="space-y-3">
      <h3 class="font-semibold">{{ t('JRC_APPROVALS.decision') }}</h3>
      <p
        v-if="!choices.length"
        class="text-sm text-n-slate-11"
      >
        {{ t('JRC_APPROVALS.noDecision') }}
      </p>
      <template v-else>
        <label class="block text-sm"
          >{{ t('JRC_APPROVALS.reason')
          }}<textarea
            v-model="reason"
            required
            class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-3"
            rows="3"
          />
        </label>
        <div class="flex flex-wrap gap-2">
          <Button
            v-for="(choice, index) in choices"
            :key="index"
            :label="`${choice.step_code}: ${choice.decision}${choice.delegation_id ? ` (#${choice.delegation_id})` : ''}`"
            :disabled="busy || !reason.trim()"
            @click="
              emit('decide', {
                ...choice,
                reason: reason.trim(),
                expected_version: request.lock_version,
              })
            "
          />
        </div>
      </template>
    </section>
    <section class="space-y-3">
      <h3 class="font-semibold">{{ t('JRC_APPROVALS.decisions') }}</h3>
      <p
        v-if="!request.decisions?.length"
        class="text-sm"
      >
        {{ t('JRC_APPROVALS.empty') }}
      </p>
      <article
        v-for="decision in request.decisions || []"
        :key="decision.id"
        class="rounded-xl border border-n-weak p-3 text-sm"
      >
        <p>
          {{ decision.step_code }} · {{ decision.decision }} ·
          {{ decision.actor_name }}
        </p>
        <p class="my-2 whitespace-pre-wrap">{{ decision.reason }}</p>
        <p class="text-xs text-n-slate-11">
          {{ decision.created_at }} · {{ t('JRC_APPROVALS.cycle') }}
          {{ decision.cycle }}
        </p>
      </article>
    </section>
    <Button
      v-if="auditAllowed"
      :label="t('JRC_APPROVALS.history')"
      variant="faded"
      @click="emit('audit')"
    />
  </section>
</template>
