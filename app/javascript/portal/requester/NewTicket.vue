<script setup>
import { computed, inject, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { catalogueAnswers } from '../../dashboard/routes/dashboard/serviceDesk/helpers/catalogueFields';
import { request, upload, submission, errorKey } from './client';

const { t } = useI18n();
const context = inject('portalContext');
const services = ref([]);
const serviceId = ref('');
const contractId = ref('');
const subject = ref('');
const description = ref('');
const answers = ref({});
const files = ref([]);
const review = ref(false);
const created = ref(null);
const busy = ref(false);
const error = ref('');
const intention = submission();
const selected = computed(() =>
  services.value.find(service => service.id === serviceId.value)
);
const input = () => ({
  service_id: selected.value.id,
  service_revision: selected.value.revision,
  title: subject.value,
  description: description.value,
  service_fields: catalogueAnswers(selected.value.form_fields, answers.value),
  ...(contractId.value ? { contract_id: contractId.value } : {}),
});
onMounted(async () => {
  busy.value = true;
  try {
    services.value = (await request('/portal/api/catalogo')).services;
  } catch (failure) {
    error.value = errorKey(failure);
  } finally {
    busy.value = false;
  }
});
watch(serviceId, () => {
  contractId.value = '';
  answers.value = Object.fromEntries(
    (selected.value?.form_fields || [])
      .filter(field => field.type === 'boolean')
      .map(field => [field.key, false])
  );
});
const prepare = () => {
  try {
    input();
    review.value = true;
    error.value = '';
  } catch (failure) {
    error.value = errorKey(failure);
  }
};
const confirm = async () => {
  if (busy.value) return;
  busy.value = true;
  try {
    const fields = input();
    const result = await request('/portal/api/chamados', {
      method: 'POST',
      body: upload({ ticket: fields }, files.value),
      headers: { 'Idempotency-Key': intention.key(fields, files.value) },
    });
    created.value = result.ticket;
    intention.reset();
    error.value = '';
  } catch (failure) {
    intention.failed(failure);
    error.value = errorKey(failure);
  } finally {
    busy.value = false;
  }
};
const updateAnswer = (field, event) => {
  const value =
    field.type === 'boolean' ? event.target.checked : event.target.value;
  answers.value[field.key] =
    field.type === 'integer' && value !== '' ? Number(value) : value;
};
const edit = () => {
  review.value = false;
};
</script>

<template>
  <section class="space-y-6">
    <h1 class="text-2xl font-semibold text-slate-900">
      {{
        t(
          created
            ? 'PORTAL.CREATED'
            : review
              ? 'PORTAL.REVIEW_TITLE'
              : 'PORTAL.NEW',
          { number: created?.number }
        )
      }}
    </h1>
    <p
      v-if="error"
      role="alert"
      class="rounded-xl bg-red-50 p-4 text-sm text-red-800"
    >
      {{ t(error) }}
    </p>
    <div
      v-if="created"
      class="rounded-2xl border border-slate-200 bg-white p-8"
    >
      <h2 class="text-lg font-semibold">{{ created.title }}</h2>
      <p class="mt-3 whitespace-pre-wrap text-sm">{{ created.description }}</p>
      <RouterLink
        :to="`/chamados/${created.id}`"
        class="mt-6 inline-block rounded-xl bg-slate-900 px-5 py-3 text-sm font-semibold text-white"
      >
        {{ t('PORTAL.FOLLOW') }}
      </RouterLink>
    </div>
    <form
      v-else
      class="space-y-6 rounded-2xl border border-slate-200 bg-white p-5 sm:p-8"
      @submit.prevent="review ? confirm() : prepare()"
    >
      <dl class="grid gap-4 rounded-xl bg-slate-50 p-4 text-sm sm:grid-cols-2">
        <div
          v-for="(value, key) in {
            NAME: context.contact.name,
            EMAIL: context.contact.email,
            PHONE: context.contact.phone_number,
            ORGANIZATION: context.organization,
          }"
          :key="key"
        >
          <dt class="text-xs text-slate-500">{{ t(`PORTAL.${key}`) }}</dt>
          <dd class="mt-1 break-words font-medium">{{ value }}</dd>
        </div>
      </dl>
      <p
        v-if="!services.length && !busy"
        class="text-sm text-slate-500"
      >
        {{ t('PORTAL.NO_CATALOGUE') }}
      </p>
      <label class="block text-sm font-semibold">
        {{ t('PORTAL.SERVICE') }}
        <select
          v-model="serviceId"
          required
          :disabled="review || busy"
          class="mt-2 w-full rounded-xl border border-slate-300 p-3"
        >
          <option value="">{{ t('PORTAL.SELECT') }}</option>
          <option
            v-for="service in services"
            :key="service.id"
            :value="service.id"
          >
            {{ service.name }}
          </option>
        </select>
      </label>
      <div
        v-if="selected"
        class="grid gap-4 text-sm sm:grid-cols-2"
      >
        <p>{{ t('PORTAL.UNIT') }}: {{ selected.unit }}</p>
        <p v-if="selected.category">
          {{ t('PORTAL.CATEGORY') }}: {{ selected.category }}
        </p>
      </div>
      <label
        v-if="selected?.contracts?.length"
        class="block text-sm font-semibold"
      >
        {{ t('PORTAL.CONTRACT') }}
        <select
          v-model="contractId"
          :required="selected.contract_required"
          :disabled="review || busy"
          class="mt-2 w-full rounded-xl border border-slate-300 p-3"
        >
          <option value="">{{ t('PORTAL.SELECT') }}</option>
          <option
            v-for="contract in selected.contracts"
            :key="contract.id"
            :value="contract.id"
          >
            {{ contract.name }}
          </option>
        </select>
      </label>
      <label class="block text-sm font-semibold">
        {{ t('PORTAL.SUBJECT') }}
        <input
          v-model="subject"
          required
          maxlength="255"
          :readonly="review"
          class="mt-2 w-full rounded-xl border border-slate-300 p-3"
        />
      </label>
      <label class="block text-sm font-semibold">
        {{ t('PORTAL.DESCRIPTION') }}
        <textarea
          v-model="description"
          required
          maxlength="20000"
          rows="5"
          :readonly="review"
          class="mt-2 w-full rounded-xl border border-slate-300 p-3"
        />
      </label>
      <label
        v-for="field in selected?.form_fields || []"
        :key="field.key"
        class="block text-sm font-semibold"
      >
        {{ field.label }}
        <select
          v-if="field.type === 'select'"
          :value="answers[field.key] || ''"
          :required="field.required"
          :disabled="review"
          class="mt-2 w-full rounded-xl border border-slate-300 p-3"
          @change="updateAnswer(field, $event)"
        >
          <option value="">{{ t('PORTAL.SELECT') }}</option>
          <option
            v-for="option in field.options"
            :key="option"
            :value="option"
          >
            {{ option }}
          </option>
        </select>
        <input
          v-else
          :type="
            field.type === 'boolean'
              ? 'checkbox'
              : field.type === 'integer'
                ? 'number'
                : 'text'
          "
          :value="answers[field.key]"
          :checked="answers[field.key] === true"
          :required="field.required && field.type !== 'boolean'"
          :disabled="review"
          class="mt-2 rounded-lg border border-slate-300 p-3"
          :class="field.type === 'boolean' ? 'ml-3' : 'w-full'"
          @change="updateAnswer(field, $event)"
        />
      </label>
      <label class="block text-sm font-semibold">
        {{ t('PORTAL.ATTACHMENTS') }}
        <input
          v-if="!review"
          type="file"
          multiple
          class="mt-2 block w-full text-sm"
          @change="files = Array.from($event.target.files)"
        />
        <span class="mt-2 block text-xs font-normal text-slate-500">
          {{ t('PORTAL.FILES_HELP') }}
        </span>
        <span
          v-for="file in files"
          :key="`${file.name}-${file.size}`"
          class="mt-2 block break-words text-sm font-normal"
        >
          {{ file.name }}
        </span>
      </label>
      <p class="text-xs text-slate-500">{{ t('PORTAL.PRIORITY_HELP') }}</p>
      <div class="flex flex-wrap gap-3">
        <button
          v-if="review"
          type="button"
          :disabled="busy"
          class="rounded-xl border border-slate-300 px-5 py-3 text-sm font-semibold"
          @click="edit"
        >
          {{ t('PORTAL.EDIT') }}
        </button>
        <button
          :disabled="busy || !selected"
          class="rounded-xl bg-slate-900 px-5 py-3 text-sm font-semibold text-white disabled:opacity-40"
        >
          {{
            t(
              busy
                ? 'PORTAL.LOADING'
                : review
                  ? 'PORTAL.CONFIRM'
                  : 'PORTAL.REVIEW'
            )
          }}
        </button>
      </div>
    </form>
  </section>
</template>
