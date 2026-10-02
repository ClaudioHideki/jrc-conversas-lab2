<script setup>
import { reactive, ref, watch, onBeforeUnmount } from 'vue';
import API from 'dashboard/api/jrcCustomers';
import CompanyPicker from './CompanyPicker.vue';
import { useCustomerMaster } from '../useCustomerMaster';
import {
  T,
  FIELD_LABELS,
  POINT_TYPES,
  inputClass,
  buttonClass,
  primaryClass,
  errorMessage,
} from '../copy';
const props = defineProps({
  contactId: { type: [Number, String], default: null },
});
const emit = defineEmits(['updated']);
const { accountId, enabled, canAdmin, accountScopedRoute } =
  useCustomerMaster();
const contact = ref(null);
const points = ref([]);
const duplicateItems = ref([]);
const checked = ref(false);
const expanded = ref(false);
const error = ref('');
const notice = ref('');
const busy = ref(false);
const form = reactive({
  company_id: null,
  job_title: '',
  department: '',
  registration_status: 'provisional',
});
const point = reactive({ kind: 'phone', value: '', label: '' });
let generation = 0;
const load = async () => {
  generation += 1;
  const version = generation;
  contact.value = null;
  error.value = '';
  checked.value = false;
  duplicateItems.value = [];
  if (!enabled.value || !props.contactId) return;
  try {
    const { data } = await API.contact(props.contactId);
    if (version !== generation) return;
    contact.value = data.payload;
    points.value = data.contact_points;
    Object.keys(form).forEach(key => {
      form[key] = data.payload[key];
    });
  } catch (err) {
    if (version === generation) error.value = errorMessage(err);
  }
};
const save = async () => {
  const changingCompany =
    contact.value.company_id &&
    String(contact.value.company_id) !== String(form.company_id);
  if (changingCompany && !window.confirm(T.confirmReassignment)) return;
  busy.value = true;
  error.value = '';
  notice.value = '';
  try {
    await API.saveContact({ ...form }, props.contactId, {
      confirm_reassignment: Boolean(changingCompany),
    });
    await load();
    emit('updated');
    notice.value = T.saved;
  } catch (err) {
    error.value = errorMessage(err);
  } finally {
    busy.value = false;
  }
};
const addPoint = async () => {
  busy.value = true;
  error.value = '';
  try {
    await API.savePoint(props.contactId, { ...point });
    point.value = '';
    point.label = '';
    await load();
  } catch (err) {
    error.value = errorMessage(err);
  } finally {
    busy.value = false;
  }
};
const removePoint = async item => {
  if (!window.confirm(T.confirmRemove)) return;
  busy.value = true;
  try {
    await API.removePoint(props.contactId, item.id);
    await load();
  } catch (err) {
    error.value = errorMessage(err);
  } finally {
    busy.value = false;
  }
};
const duplicates = async () => {
  busy.value = true;
  error.value = '';
  try {
    const { data } = await API.duplicates(props.contactId);
    duplicateItems.value = data.payload;
    checked.value = true;
  } catch (err) {
    error.value = errorMessage(err);
  } finally {
    busy.value = false;
  }
};
const merge = async item => {
  if (!window.confirm(T.confirmMerge)) return;
  busy.value = true;
  error.value = '';
  try {
    await API.merge(props.contactId, item.id);
    await load();
    emit('updated');
  } catch (err) {
    error.value = errorMessage(err);
  } finally {
    busy.value = false;
  }
};
watch([accountId, enabled, () => props.contactId], load, { immediate: true });
onBeforeUnmount(() => {
  generation += 1;
});
</script>

<template>
  <section
    v-if="enabled && contactId"
    class="m-3 rounded-xl border border-n-weak bg-n-solid-2 p-4 text-n-slate-12"
  >
    <button
      type="button"
      class="flex w-full items-center justify-between text-left font-semibold"
      :aria-expanded="expanded"
      @click="expanded = !expanded"
    >
      <span>{{ T.master }}</span
      ><span>{{ expanded ? '\u2212' : '+' }}</span>
    </button>
    <p
      v-if="error"
      class="mt-3 text-sm text-n-ruby-11"
      role="alert"
    >
      {{ error }}
    </p>
    <p
      v-if="notice"
      class="mt-2 text-sm"
      role="status"
    >
      {{ notice }}
    </p>
    <template v-if="contact"
      ><p class="mt-2 text-xs text-n-slate-10">
        {{
          contact.registration_status === 'registered'
            ? T.registered
            : T.provisional
        }}
      </p>
      <RouterLink
        v-if="contact.company_id"
        :to="
          accountScopedRoute('jrc_customer_company', {
            companyId: contact.company_id,
          })
        "
        class="mt-2 block text-sm font-medium text-n-brand"
        >{{ contact.company_name || `#${contact.company_id}` }} /
        {{ T.openCompany }}</RouterLink
      >
      <p
        v-else
        class="mt-2 text-sm"
      >
        {{ T.noCompany }}
      </p>
      <div
        v-if="expanded"
        class="mt-4 space-y-4"
      >
        <p class="text-xs text-n-slate-10">{{ T.provisionalHelp }}</p>
        <form @submit.prevent="save">
          <fieldset
            :disabled="busy"
            class="space-y-3"
          >
            <CompanyPicker v-model="form.company_id" /><RouterLink
              :to="
                accountScopedRoute(
                  'jrc_customer_companies',
                  {},
                  { create: '1' }
                )
              "
              class="block text-xs text-n-brand"
              >{{ T.newCompany }}</RouterLink
            >
            <label
              v-for="field in ['job_title', 'department']"
              :key="field"
              class="block text-sm"
              >{{ FIELD_LABELS[field]
              }}<input
                v-model.trim="form[field]"
                maxlength="255"
                :class="inputClass"
            /></label>
            <label class="block text-sm"
              >{{ T.kind
              }}<select
                v-model="form.registration_status"
                :class="inputClass"
              >
                <option value="provisional">{{ T.provisional }}</option>
                <option value="registered">{{ T.registered }}</option>
              </select></label
            >
            <button
              :class="primaryClass"
              :disabled="busy"
            >
              {{ T.saveLink }}
            </button>
          </fieldset>
        </form>
        <div class="border-t border-n-weak pt-3">
          <h4 class="text-sm font-semibold">{{ T.contactPoints }}</h4>
          <p class="mt-1 text-xs text-n-slate-10">{{ T.pointHelp }}</p>
          <ul class="my-3 space-y-2">
            <li
              v-for="item in points"
              :key="item.id"
              class="flex items-start justify-between gap-2 text-xs"
            >
              <span class="break-all"
                >{{ POINT_TYPES[item.kind] }}: {{ item.value }}
                {{ item.label }}</span
              ><button
                type="button"
                :class="buttonClass"
                :disabled="busy"
                @click="removePoint(item)"
              >
                {{ T.remove }}
              </button>
            </li>
          </ul>
          <form
            class="space-y-2"
            @submit.prevent="addPoint"
          >
            <select
              v-model="point.kind"
              :aria-label="T.kind"
              :class="inputClass"
            >
              <option
                v-for="(label, key) in POINT_TYPES"
                :key="key"
                :value="key"
              >
                {{ label }}
              </option></select
            ><input
              v-model.trim="point.value"
              required
              maxlength="255"
              :aria-label="T.value"
              :placeholder="T.value"
              :class="inputClass"
            /><input
              v-model.trim="point.label"
              maxlength="255"
              :aria-label="T.label"
              :placeholder="T.label"
              :class="inputClass"
            /><button
              :class="buttonClass"
              :disabled="busy"
            >
              {{ T.addPoint }}
            </button>
          </form>
        </div>
        <button
          type="button"
          :class="buttonClass"
          :disabled="busy"
          @click="duplicates"
        >
          {{ T.duplicates }}
        </button>
        <p
          v-if="checked && !duplicateItems.length"
          class="text-xs"
        >
          {{ T.noDuplicates }}
        </p>
        <article
          v-for="item in duplicateItems"
          :key="item.id"
          class="rounded-lg border border-n-weak p-2 text-xs"
        >
          <RouterLink
            :to="accountScopedRoute('contacts_edit', { contactId: item.id })"
            class="font-semibold text-n-brand"
            >{{ item.name }} #{{ item.id }}</RouterLink
          >
          <p>
            {{ item.company_name }} {{ item.phone_number }} {{ item.email }}
          </p>
          <button
            v-if="canAdmin"
            type="button"
            :class="buttonClass"
            :disabled="busy"
            @click="merge(item)"
          >
            {{ T.merge }}
          </button>
        </article>
      </div>
    </template>
  </section>
</template>
