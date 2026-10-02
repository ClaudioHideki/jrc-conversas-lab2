<script setup>
import { reactive, ref } from 'vue';
import API from 'dashboard/api/jrcCustomers';
import {
  T,
  FIELD_LABELS,
  ADDRESS_TYPES,
  inputClass,
  buttonClass,
  primaryClass,
  errorMessage,
} from '../copy';
const props = defineProps({
  companyId: { type: [Number, String], required: true },
  addresses: { type: Array, default: () => [] },
});
const emit = defineEmits(['changed']);
const fields = [
  'postal_code',
  'street',
  'number',
  'complement',
  'district',
  'city',
  'state',
  'country',
];
const form = reactive({});
const editing = ref(false);
const id = ref(null);
const error = ref('');
const busy = ref(false);
const edit = row => {
  fields.forEach(key => {
    form[key] = row?.[key] || (key === 'country' ? 'BR' : '');
  });
  form.address_type = row?.address_type || 'business';
  id.value = row?.id || null;
  editing.value = true;
  error.value = '';
};
const save = async () => {
  busy.value = true;
  error.value = '';
  try {
    await API.saveAddress(props.companyId, { ...form }, id.value);
    editing.value = false;
    emit('changed');
  } catch (err) {
    error.value = errorMessage(err);
  } finally {
    busy.value = false;
  }
};
const remove = async row => {
  if (!window.confirm(T.confirmRemove)) return;
  busy.value = true;
  try {
    await API.removeAddress(props.companyId, row.id);
    emit('changed');
  } catch (err) {
    error.value = errorMessage(err);
  } finally {
    busy.value = false;
  }
};
</script>

<template>
  <section>
    <button
      type="button"
      :class="primaryClass"
      :disabled="busy"
      @click="edit(null)"
    >
      {{ T.addAddress }}
    </button>
    <p
      v-if="error"
      class="my-3 text-n-ruby-11"
      role="alert"
    >
      {{ error }}
    </p>
    <form
      v-if="editing"
      class="my-4 rounded-xl border border-n-weak p-4"
      @submit.prevent="save"
    >
      <fieldset
        :disabled="busy"
        class="grid gap-3 md:grid-cols-3"
      >
        <label class="text-sm"
          >{{ T.kind
          }}<select
            v-model="form.address_type"
            :class="inputClass"
          >
            <option
              v-for="(label, key) in ADDRESS_TYPES"
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
            :required="field === 'country'"
            maxlength="255"
            :class="inputClass"
        /></label>
      </fieldset>
      <div class="mt-4 flex gap-2">
        <button
          :class="primaryClass"
          :disabled="busy"
        >
          {{ T.save }}</button
        ><button
          type="button"
          :class="buttonClass"
          @click="editing = false"
        >
          {{ T.cancel }}
        </button>
      </div>
    </form>
    <p
      v-if="!addresses.length"
      class="my-4 text-n-slate-10"
    >
      {{ T.noResults }}
    </p>
    <div class="mt-4 grid gap-4 md:grid-cols-2">
      <article
        v-for="address in addresses"
        :key="address.id"
        class="rounded-xl border border-n-weak p-4"
      >
        <h3 class="font-semibold">{{ ADDRESS_TYPES[address.address_type] }}</h3>
        <p class="mt-2 text-sm">
          {{ address.street }}, {{ address.number }} {{ address.complement }}
        </p>
        <p class="text-sm">
          {{ address.district }} {{ address.city }} {{ address.state }}
          {{ address.country }}
        </p>
        <p class="text-sm">{{ address.postal_code }}</p>
        <div class="mt-3 flex gap-2">
          <button
            type="button"
            :class="buttonClass"
            @click="edit(address)"
          >
            {{ T.edit }}</button
          ><button
            type="button"
            :class="buttonClass"
            :disabled="busy"
            @click="remove(address)"
          >
            {{ T.remove }}
          </button>
        </div>
      </article>
    </div>
  </section>
</template>
