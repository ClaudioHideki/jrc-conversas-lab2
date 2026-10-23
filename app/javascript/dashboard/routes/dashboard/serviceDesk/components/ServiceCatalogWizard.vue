<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ConfigurationV2Fields from './ConfigurationV2Fields.vue';
import ServiceDeskStepper from './ServiceDeskStepper.vue';
import { CATALOG_STEPS, nextStep } from '../helpers/presentationSteps';
import { serviceDeskRouteName } from '../routeDefinitions';
const props = defineProps({
  modelValue: { type: Object, required: true },
  record: { type: Object, required: true },
  unitId: { type: String, required: true },
  context: { type: Object, required: true },
  saving: Boolean,
  pending: Boolean,
  feedback: { type: String, default: 'idle' },
});
const emit = defineEmits(['update:modelValue', 'save', 'cancel']);
const { t } = useI18n();
const step = ref('information');
const locked = computed(() => props.saving || props.pending);
const draft = computed({
  get: () => props.modelValue,
  set: value => emit('update:modelValue', value),
});
const set = (field, value) =>
  emit('update:modelValue', { ...props.modelValue, [field]: value });
const accountId = computed(() => props.context.account_id);
const move = offset => {
  if (!locked.value) step.value = nextStep(CATALOG_STEPS, step.value, offset);
};
const finish = () => {
  if (props.saving) return;
  if (step.value !== 'publication') {
    move(1);
    return;
  }
  emit('save');
};
</script>

<template>
  <form class="grid gap-4" data-service-catalog-wizard @submit.prevent="finish">
    <ServiceDeskStepper
      v-model="step"
      :steps="CATALOG_STEPS"
      :disabled="locked"
      label-root="JRC_SERVICE_DESK.REFINEMENT.catalog.steps"
      :label="t('JRC_SERVICE_DESK.REFINEMENT.catalog.title')"
    />
    <p class="rounded-lg bg-n-blue-2 p-3 text-sm">
      {{ t('JRC_SERVICE_DESK.REFINEMENT.catalog.save_notice') }}
    </p>
    <div
      class="grid min-w-0 items-start gap-4 lg:grid-cols-[minmax(0,1fr)_16rem]"
    >
      <section class="grid min-w-0 gap-4">
        <h3 class="font-semibold">
          {{ t(`JRC_SERVICE_DESK.REFINEMENT.catalog.steps.${step}`) }}
        </h3>
        <div v-if="step === 'information'" class="grid gap-3">
          <Input
            :model-value="draft.name"
            :disabled="locked"
            maxlength="255"
            :label="t('JRC_SERVICE_DESK.FIELDS.name')"
            @update:model-value="set('name', $event)"
          />
          <Input
            :model-value="draft.code"
            :disabled="!!record.id || locked"
            maxlength="80"
            :label="t('JRC_SERVICE_DESK.FIELDS.code')"
            @update:model-value="set('code', $event)"
          />
          <Input
            v-if="Object.hasOwn(draft, 'position')"
            :model-value="draft.position"
            type="number"
            min="0"
            :disabled="locked"
            :label="t('JRC_SERVICE_DESK.ADMIN.position')"
            @update:model-value="set('position', $event)"
          />
        </div>
        <ConfigurationV2Fields
          v-model="draft"
          resource="services"
          :section="step"
          :unit-id="unitId"
          :context="context"
          :disabled="locked"
        />
        <div
          v-if="step === 'rules'"
          class="rounded-xl border border-n-weak bg-n-blue-2 p-4 text-sm"
        >
          <h4 class="mb-2 font-semibold">
            {{ t('JRC_SERVICE_DESK.REFINEMENT.catalog.sla_title') }}
          </h4>
          <p>{{ t('JRC_SERVICE_DESK.REFINEMENT.catalog.sla_help') }}</p>
          <RouterLink
            v-if="context.capabilities?.lifecycle_policies?.publish"
            class="mt-3 inline-block text-n-blue-11 underline"
            target="_blank"
            rel="noopener noreferrer"
            :to="{
              name: serviceDeskRouteName('automations'),
              params: { accountId },
              query: {
                section: 'lifecycle',
                unit_id: unitId,
                service_id: record.id || undefined,
              },
            }"
          >
            {{ t('JRC_SERVICE_DESK.REFINEMENT.catalog.open_policy') }}
          </RouterLink>
        </div>
        <div
          v-if="step === 'publication'"
          class="grid gap-3 rounded-xl border border-n-weak p-4"
        >
          <label class="flex gap-2 text-sm"
            ><input
              type="checkbox"
              :checked="draft.active"
              :disabled="locked"
              @change="set('active', $event.target.checked)"
            />
            {{ t('JRC_SERVICE_DESK.ADMIN.active_label') }}</label
          >
          <p class="text-sm">
            {{ t('JRC_SERVICE_DESK.ADMIN.deactivation_warning') }}
          </p>
          <dl class="grid gap-3 text-sm sm:grid-cols-2">
            <div>
              <dt class="text-n-slate-11">
                {{ t('JRC_SERVICE_DESK.FIELDS.name') }}
              </dt>
              <dd>{{ draft.name || t('JRC_SERVICE_DESK.COMMON.no_value') }}</dd>
            </div>
            <div>
              <dt class="text-n-slate-11">
                {{ t('JRC_SERVICE_DESK.FIELDS.code') }}
              </dt>
              <dd>{{ draft.code || t('JRC_SERVICE_DESK.COMMON.no_value') }}</dd>
            </div>
            <div>
              <dt class="text-n-slate-11">
                {{ t('JRC_SERVICE_DESK.V2_SETTINGS.catalogue') }}
              </dt>
              <dd>{{ draft.form_fields?.length || 0 }}</dd>
            </div>
            <div>
              <dt class="text-n-slate-11">
                {{ t('JRC_SERVICE_DESK.V2_SETTINGS.approval_required') }}
              </dt>
              <dd>
                {{
                  t(
                    `JRC_SERVICE_DESK.REFINEMENT.${draft.approval_required ? 'yes' : 'no'}`
                  )
                }}
              </dd>
            </div>
          </dl>
        </div>
      </section>
      <aside
        class="grid min-w-0 gap-3 rounded-xl border border-n-weak bg-n-solid-1 p-4 lg:sticky lg:top-3"
      >
        <h3 class="text-sm font-semibold">
          {{ t('JRC_SERVICE_DESK.REFINEMENT.catalog.preview') }}
        </h3>
        <div class="rounded-xl border border-n-blue-5 bg-n-blue-2 p-4">
          <span
            class="i-lucide-headset mb-3 block size-6 text-n-blue-11"
            aria-hidden="true"
          />
          <strong class="block break-words">{{
            draft.name || t('JRC_SERVICE_DESK.CATALOG.new_record')
          }}</strong>
          <p
            class="mt-2 whitespace-pre-wrap break-words text-xs text-n-slate-11"
          >
            {{ draft.description || t('JRC_SERVICE_DESK.COMMON.not_informed') }}
          </p>
          <span
            class="mt-3 inline-block rounded-full bg-n-solid-1 px-2 py-1 text-xs"
            >{{
              t(
                `JRC_SERVICE_DESK.COMMON.${draft.active ? 'active' : 'inactive'}`
              )
            }}</span
          >
        </div>
        <p class="text-xs text-n-slate-11">
          {{ t('JRC_SERVICE_DESK.REFINEMENT.catalog.preview_notice') }}
        </p>
      </aside>
    </div>
    <p v-if="feedback !== 'idle'" role="status" class="text-sm">
      {{ t(`JRC_SERVICE_DESK.ADMIN.feedback.${feedback}`) }}
    </p>
    <footer
      class="sticky bottom-0 flex flex-wrap items-center justify-between gap-2 border-t border-n-weak bg-n-solid-1 py-3"
    >
      <div class="flex gap-2">
        <Button
          type="button"
          variant="ghost"
          :disabled="locked"
          :label="t('JRC_SERVICE_DESK.COMMON.cancel')"
          @click="emit('cancel')"
        />
        <Button
          v-if="step !== 'information'"
          type="button"
          variant="outline"
          :disabled="locked"
          :label="t('JRC_SERVICE_DESK.REFINEMENT.back')"
          @click="move(-1)"
        />
      </div>
      <Button
        v-if="step !== 'publication'"
        type="button"
        :disabled="locked"
        :label="t('JRC_SERVICE_DESK.COMMON.next')"
        @click="move(1)"
      />
      <Button
        v-else
        type="submit"
        :disabled="saving || !unitId"
        :label="
          t(
            pending
              ? 'JRC_SERVICE_DESK.ADMIN.retry_same'
              : 'JRC_SERVICE_DESK.COMMON.save'
          )
        "
      />
    </footer>
  </form>
</template>
