<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { filePath, request } from './client';

const props = defineProps({
  base: { type: String, required: true },
  setup: { type: Object, required: true },
  materials: Boolean,
});
const emit = defineEmits(['changed', 'expired']);
const { t } = useI18n();
const busy = ref(false);
const feedback = ref('');
const error = ref(false);
const actions = {
  draft: ['publish', 'withdraw'],
  published: ['deactivate', 'withdraw'],
  inactive: ['publish', 'withdraw'],
  withdrawn: [],
};
const manualOptions = computed(() => {
  const byManual = new Map();
  props.setup.versions
    .filter(version => version.manageable)
    .forEach(version => {
      if (!byManual.has(version.manual_id))
        byManual.set(version.manual_id, version.title);
    });
  return [...byManual.entries()];
});
const input = 'min-w-0 rounded-lg border border-n-weak bg-n-solid-2 px-3 py-2';
const button =
  'rounded-lg border border-n-weak px-3 py-2 text-sm font-medium hover:bg-n-solid-3 disabled:opacity-50';

async function submit(path, body, form) {
  if (busy.value) return;
  busy.value = true;
  error.value = false;
  feedback.value = '';
  try {
    await request(path, { method: 'POST', body });
    form?.reset();
    feedback.value = 'saved';
    emit('changed');
  } catch (failure) {
    if (failure.status === 401) emit('expired');
    else {
      error.value = true;
      feedback.value =
        form && failure.status === 422 ? 'file_unavailable' : 'error';
    }
  } finally {
    busy.value = false;
  }
}

function createVersion(event) {
  const form = event.currentTarget;
  const fields = new FormData(form);
  if (!fields.get('pptx')?.size) fields.delete('pptx');
  submit(`${props.base}/admin/versions`, fields, form);
}

function transition(id, action) {
  submit(`${props.base}/admin/versions/${id}/transition`, {
    transition: action,
  });
}
</script>

<template>
  <div class="grid gap-4">
    <form
      v-if="!materials"
      class="grid gap-3 rounded-xl border border-n-weak bg-n-solid-1 p-4 sm:grid-cols-2"
      @submit.prevent="createVersion"
    >
      <h3 class="font-semibold sm:col-span-2">{{ t('new_version') }}</h3>
      <label class="grid gap-1 text-sm">
        {{ t('publication') }}
        <select name="manual_id" :class="input">
          <option value="">{{ t('new_manual') }}</option>
          <option v-for="[id, title] in manualOptions" :key="id" :value="id">
            {{ title }}
          </option>
        </select>
      </label>
      <label class="grid gap-1 text-sm">
        {{ t('title_field') }}
        <input name="title" maxlength="150" :class="input" required />
      </label>
      <label class="grid gap-1 text-sm sm:col-span-2">
        {{ t('description') }}
        <textarea name="description" rows="2" maxlength="4000" :class="input" />
      </label>
      <fieldset
        class="grid gap-2 rounded-lg border border-n-weak p-3 sm:col-span-2"
      >
        <legend class="px-1 text-sm">{{ t('public') }}</legend>
        <label
          v-for="unit in setup.units"
          :key="unit.id"
          class="flex items-start gap-2 text-sm"
        >
          <input
            type="checkbox"
            class="mt-0.5"
            name="unit_ids[]"
            :value="unit.id"
          />
          <span>{{ unit.company }} · {{ unit.name }}</span>
        </label>
      </fieldset>
      <label class="grid gap-1 text-sm">
        {{ t('pdf_required') }}
        <input
          name="pdf"
          required
          type="file"
          accept="application/pdf,.pdf"
          :class="input"
        />
      </label>
      <label class="grid gap-1 text-sm">
        {{ t('pptx_optional') }}
        <input name="pptx" type="file" accept=".pptx" :class="input" />
      </label>
      <div>
        <button
          class="rounded-lg bg-blue-700 px-4 py-2 font-semibold text-white disabled:opacity-50"
          :disabled="busy"
        >
          {{ t(busy ? 'busy' : 'create_draft') }}
        </button>
      </div>
    </form>
    <p
      v-if="feedback"
      :class="error ? 'text-n-ruby-11' : 'text-n-teal-11'"
      :role="error ? 'alert' : 'status'"
    >
      {{ t(feedback) }}
    </p>
    <p
      v-if="!setup.versions.length"
      class="rounded-xl border border-n-weak bg-n-solid-1 p-4 text-n-slate-11"
    >
      {{ t('empty') }}
    </p>
    <article
      v-for="item in setup.versions"
      :key="item.id"
      class="grid gap-3 rounded-xl border border-n-weak bg-n-solid-1 p-4"
    >
      <div class="flex flex-wrap items-center justify-between gap-2">
        <h3 class="break-words font-semibold">
          {{ item.title }} · {{ t('published', { number: item.number }) }}
        </h3>
        <span class="rounded-full bg-n-solid-3 px-2 py-1 text-xs">{{
          t(`version_states.${item.state}`)
        }}</span>
      </div>
      <p v-if="item.description" class="break-words text-sm text-n-slate-11">
        {{ item.description }}
      </p>
      <p class="text-sm text-n-slate-11">
        {{
          setup.units
            .filter(unit => item.unit_ids.includes(unit.id))
            .map(unit => unit.name)
            .join(' · ')
        }}
      </p>
      <div class="flex flex-wrap gap-2">
        <a
          v-for="file in item.files"
          :key="file.kind"
          :class="button"
          :href="filePath(`${base}/admin`, item.id, file.kind)"
          >{{ t(file.kind) }}</a
        >
        <template v-if="!materials && item.manageable">
          <button
            v-for="action in actions[item.state]"
            :key="action"
            :class="button"
            :disabled="busy"
            @click="transition(item.id, action)"
          >
            {{ t(action) }}
          </button>
        </template>
      </div>
    </article>
  </div>
</template>
