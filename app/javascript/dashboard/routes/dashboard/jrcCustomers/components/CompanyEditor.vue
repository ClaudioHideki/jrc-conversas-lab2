<script setup>
import { reactive, ref, watch, onMounted } from 'vue';
import API from 'dashboard/api/jrcCustomers';
import CompanyPicker from './CompanyPicker.vue';
import {
  T,
  FIELD_LABELS,
  RELATIONSHIPS,
  PERSON_KINDS,
  inputClass,
  buttonClass,
  primaryClass,
  errorMessage,
} from '../copy';
const props = defineProps({ company: { type: Object, default: null } });
const emit = defineEmits(['saved', 'cancel']);
const fields = [
  'name',
  'trade_name',
  'tax_id',
  'state_registration',
  'municipal_registration',
  'segment',
  'size',
  'website',
  'domain',
  'email',
  'phone_number',
  'source',
  'economic_group',
];
const form = reactive({});
const owners = ref([]);
const error = ref('');
const busy = ref(false);
watch(
  () => props.company,
  value => {
    fields.forEach(key => {
      form[key] = value?.[key] || '';
    });
    Object.assign(form, {
      person_kind: value?.person_kind || 'organization',
      relationship_type: value?.relationship_type || 'prospect',
      owner_id: value?.owner_id || null,
      parent_company_id: value?.parent_company_id || null,
      active: value?.active ?? true,
      description: value?.description || '',
    });
  },
  { immediate: true }
);
onMounted(async () => {
  try {
    owners.value = (await API.metadata()).data.owners;
  } catch (err) {
    error.value = errorMessage(err);
  }
});
const save = async () => {
  busy.value = true;
  error.value = '';
  try {
    const { data } = await API.saveCompany(
      { ...form, revision: props.company?.revision },
      props.company?.id
    );
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
    <h2 class="mb-4 text-xl font-semibold">
      {{ company ? T.editCompany : T.newCompany }}
    </h2>
    <p class="mb-4 text-sm text-n-slate-10">{{ T.directoryHelp }}</p>
    <fieldset
      :disabled="busy"
      class="grid gap-4 md:grid-cols-2 xl:grid-cols-3"
    >
      <label class="text-sm"
        >{{ T.kind
        }}<select
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
        </select></label
      >
      <label
        v-for="field in fields"
        :key="field"
        class="text-sm"
        >{{ FIELD_LABELS[field]
        }}<input
          v-model.trim="form[field]"
          :required="field === 'name'"
          :maxlength="field === 'name' ? 255 : 1000"
          :type="field === 'email' ? 'email' : 'text'"
          :class="inputClass"
      /></label>
      <label class="text-sm"
        >{{ T.relationship
        }}<select
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
        </select></label
      >
      <label class="text-sm"
        >{{ T.owner
        }}<select
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
        </select></label
      >
      <div class="text-sm md:col-span-2">
        <p>{{ T.parent }}</p>
        <CompanyPicker
          v-model="form.parent_company_id"
          :exclude-id="company?.id"
        />
      </div>
      <label class="flex items-center gap-2 text-sm"
        ><input
          v-model="form.active"
          type="checkbox"
        />{{ T.active }}</label
      >
      <label class="text-sm md:col-span-2"
        >{{ FIELD_LABELS.description
        }}<textarea
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
        {{ busy ? T.saving : T.save }}</button
      ><button
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
