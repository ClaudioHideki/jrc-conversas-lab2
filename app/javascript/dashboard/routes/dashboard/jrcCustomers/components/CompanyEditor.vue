<script setup>
import { computed, reactive, ref, watch, onMounted } from 'vue';
import API from 'dashboard/api/jrcCustomers';
import CompanyPicker from './CompanyPicker.vue';
import {
  T,
  FIELD_LABELS,
  RELATIONSHIPS,
  PERSON_KINDS,
  SIZE_OPTIONS,
  SOURCE_OPTIONS,
  inputClass,
  buttonClass,
  primaryClass,
  errorMessage,
} from '../copy';

const props = defineProps({ company: { type: Object, default: null } });
const emit = defineEmits(['saved', 'cancel']);

const textFields = [
  'name',
  'trade_name',
  'tax_id',
  'state_registration',
  'municipal_registration',
  'website',
  'domain',
  'email',
  'phone_number',
  'economic_group',
];

const form = reactive({});
const owners = ref([]);
const metadata = ref({ segments: [] });
const error = ref('');
const busy = ref(false);

const secondaryRelationships = computed(() =>
  Object.entries(RELATIONSHIPS).filter(
    ([key]) => key !== form.relationship_type
  )
);

watch(
  () => props.company,
  value => {
    textFields.forEach(key => {
      form[key] = value?.[key] || '';
    });
    Object.assign(form, {
      person_kind: value?.person_kind || 'organization',
      relationship_type: value?.relationship_type || 'prospect',
      relationship_tags: Array.isArray(value?.relationship_tags)
        ? [...value.relationship_tags]
        : [],
      tagsText: Array.isArray(value?.tags) ? value.tags.join(', ') : '',
      segment: value?.segment || '',
      size: value?.size || '',
      source: value?.source || '',
      owner_id: value?.owner_id || null,
      parent_company_id: value?.parent_company_id || null,
      active: value?.active ?? true,
      description: value?.description || '',
    });
  },
  { immediate: true }
);

watch(
  () => form.relationship_type,
  value => {
    form.relationship_tags = (form.relationship_tags || []).filter(
      item => item !== value
    );
  }
);

onMounted(async () => {
  try {
    const { data } = await API.metadata();
    owners.value = data.owners || [];
    metadata.value = data;
  } catch (err) {
    error.value = errorMessage(err);
  }
});

const save = async () => {
  busy.value = true;
  error.value = '';
  try {
    const tags = String(form.tagsText || '')
      .split(',')
      .map(value => value.trim())
      .filter(Boolean)
      .filter((value, index, values) => values.indexOf(value) === index)
      .slice(0, 50);
    const payload = { ...form, tags, revision: props.company?.revision };
    delete payload.tagsText;
    payload.relationship_tags = (payload.relationship_tags || []).filter(
      value => value !== payload.relationship_type
    );
    const { data } = await API.saveCompany(payload, props.company?.id);
    emit('saved', data.payload);
  } catch (err) {
    error.value = errorMessage(err);
  } finally {
    busy.value = false;
  }
};
</script>

<template>
  <form
    class="rounded-xl border border-n-weak bg-n-solid-2 p-5"
    @submit.prevent="save"
  >
    <div class="mb-4 flex flex-wrap items-start justify-between gap-3">
      <div>
        <h2 class="text-xl font-semibold">
          {{ company ? T.editCompany : T.newCompany }}
        </h2>
        <p class="mt-1 text-sm text-n-slate-10">{{ T.directoryHelp }}</p>
      </div>
      <span
        v-if="company?.customer_code"
        class="rounded-lg bg-n-alpha-2 px-3 py-2 text-sm font-semibold"
      >
        {{ company.customer_code }}
      </span>
    </div>

    <fieldset
      :disabled="busy"
      class="grid gap-4 md:grid-cols-2 xl:grid-cols-3"
    >
      <label class="text-sm">
        {{ T.kind }}
        <select
          v-model="form.person_kind"
          :class="inputClass"
        >
          <option
            v-for="(label, key) in PERSON_KINDS"
            :key="key"
            :value="key"
          >
            {{ label }}
          </option>
        </select>
      </label>

      <label
        v-for="field in textFields"
        :key="field"
        class="text-sm"
      >
        {{ FIELD_LABELS[field] }}
        <input
          v-model.trim="form[field]"
          :required="field === 'name'"
          :maxlength="field === 'name' ? 255 : 1000"
          :type="field === 'email' ? 'email' : 'text'"
          :class="inputClass"
        />
      </label>

      <label class="text-sm">
        {{ FIELD_LABELS.segment }}
        <select
          v-model="form.segment"
          :class="inputClass"
        >
          <option value="">—</option>
          <option
            v-for="value in metadata.segments || []"
            :key="value"
            :value="value"
          >
            {{ value }}
          </option>
        </select>
      </label>

      <label class="text-sm">
        {{ FIELD_LABELS.size }}
        <select
          v-model="form.size"
          :class="inputClass"
        >
          <option value="">—</option>
          <option
            v-for="(label, key) in SIZE_OPTIONS"
            :key="key"
            :value="key"
          >
            {{ label }}
          </option>
        </select>
      </label>

      <label class="text-sm">
        {{ FIELD_LABELS.source }}
        <select
          v-model="form.source"
          :class="inputClass"
        >
          <option value="">—</option>
          <option
            v-for="(label, key) in SOURCE_OPTIONS"
            :key="key"
            :value="key"
          >
            {{ label }}
          </option>
        </select>
      </label>

      <label class="text-sm">
        {{ T.relationship }}
        <select
          v-model="form.relationship_type"
          :class="inputClass"
        >
          <option
            v-for="(label, key) in RELATIONSHIPS"
            :key="key"
            :value="key"
          >
            {{ label }}
          </option>
        </select>
      </label>

      <label class="text-sm">
        {{ T.owner }}
        <select
          v-model="form.owner_id"
          :class="inputClass"
        >
          <option :value="null">{{ T.noOwner }}</option>
          <option
            v-for="owner in owners"
            :key="owner.id"
            :value="owner.id"
          >
            {{ owner.name }}
          </option>
        </select>
      </label>

      <div class="text-sm md:col-span-2">
        <p>{{ T.parent }}</p>
        <CompanyPicker
          v-model="form.parent_company_id"
          :exclude-id="company?.id"
        />
      </div>

      <div class="text-sm md:col-span-2 xl:col-span-3">
        <p class="mb-2 font-medium">{{ T.secondaryRelationships }}</p>
        <div class="flex flex-wrap gap-2">
          <label
            v-for="[key, label] in secondaryRelationships"
            :key="key"
            class="flex items-center gap-2 rounded-lg border border-n-weak px-3 py-2"
          >
            <input
              v-model="form.relationship_tags"
              type="checkbox"
              :value="key"
            />
            {{ label }}
          </label>
        </div>
      </div>

      <label class="text-sm md:col-span-2 xl:col-span-3">
        {{ T.tags }}
        <input
          v-model="form.tagsText"
          :class="inputClass"
          maxlength="2000"
          :placeholder="T.tags"
        />
      </label>

      <label class="flex items-center gap-2 text-sm">
        <input
          v-model="form.active"
          type="checkbox"
        />{{ T.active }}
      </label>

      <label class="text-sm md:col-span-2 xl:col-span-3">
        {{ FIELD_LABELS.description }}
        <textarea
          v-model="form.description"
          rows="3"
          maxlength="10000"
          :class="inputClass"
        />
      </label>
    </fieldset>

    <p
      v-if="error"
      class="mt-4 text-sm text-n-ruby-11"
      role="alert"
    >
      {{ error }}
    </p>
    <div class="mt-5 flex gap-3">
      <button
        type="submit"
        :class="primaryClass"
        :disabled="busy"
      >
        {{ busy ? T.saving : T.save }}
      </button>
      <button
        type="button"
        :class="buttonClass"
        :disabled="busy"
        @click="emit('cancel')"
      >
        {{ T.cancel }}
      </button>
    </div>
  </form>
</template>
