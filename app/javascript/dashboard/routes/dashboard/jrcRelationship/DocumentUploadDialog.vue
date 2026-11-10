<script setup>
import { onMounted, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import DocumentRequirementField from './DocumentRequirementField.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { buttonClass, inputClass } from './definitions';
const props = defineProps({
  document: { type: Object, default: null },
  busy: Boolean,
  requirements: { type: Array, default: () => [] },
  error: { type: String, default: '' },
});
const emit = defineEmits(['close', 'save']);
const { t } = useI18n();
const dialog = ref(null);
const tab = ref('file');
const form = reactive({
  requirement_key: props.document?.requirement_key || '',
  title: props.document?.title || '',
  category: props.document?.category || 'registration',
  confidentiality: props.document?.confidentiality || '',
  valid_until: '',
  change_reason: '',
});
const file = ref(null);
watch(
  () => form.category,
  () => {
    if (!props.document) form.requirement_key = '';
  }
);
onMounted(() => dialog.value.open());
</script>

<template>
  <Dialog
    ref="dialog"
    width="2xl"
    :title="
      t(
        document
          ? 'RELATIONSHIP.V2.DOCS.NEW_VERSION'
          : 'RELATIONSHIP.V2.DOCS.UPLOAD'
      )
    "
    :show-confirm-button="false"
    :show-cancel-button="false"
    :dismissible="!busy"
    @close="emit('close')"
  >
    <form
      class="space-y-4"
      @submit.prevent="emit('save', { ...form, file })"
    >
      <nav
        class="flex gap-2"
        :aria-label="t('RELATIONSHIP.V2.DOCS.UPLOAD')"
      >
        <button
          v-for="key in ['file', 'validity']"
          :key="key"
          type="button"
          :class="[
            buttonClass,
            tab === key && 'border-n-violet-8 text-n-violet-11 ',
          ]"
          :aria-pressed="tab === key"
          @click="tab = key"
        >
          {{ t(`RELATIONSHIP.V2.DOCS.TABS.${key}`) }}
        </button>
      </nav>
      <p
        v-if="error"
        role="alert"
        class="text-n-ruby-11"
      >
        {{ error }}
      </p>
      <div
        v-show="tab === 'file'"
        class="space-y-3"
      >
        <label class="block text-sm"
          >{{ t('RELATIONSHIP.V2.DOCS.TITLE')
          }}<input
            v-model="form.title"
            required
            maxlength="160"
            :disabled="!!document"
            :class="inputClass" /></label
        ><label class="block text-sm"
          >{{ t('RELATIONSHIP.V2.DOCS.CATEGORY')
          }}<select
            v-model="form.category"
            :class="inputClass"
            :disabled="!!document"
          >
            <option
              v-for="category in [
                'registration',
                'contract',
                'evidence',
                'other',
              ]"
              :key="category"
              :value="category"
            >
              {{ t(`RELATIONSHIP.V2.DOCS.CATEGORIES.${category}`) }}
            </option>
          </select></label
        >
        <label
          v-if="!document"
          class="block text-sm"
        >
          {{ t('RELATIONSHIP.V2.DOCS.CONFIDENTIALITY') }}
          <select
            v-model="form.confidentiality"
            required
            :disabled="busy"
            :class="inputClass"
          >
            <option
              value=""
              disabled
            >
              {{ t('RELATIONSHIP.V2.DOCS.CLASSIFY') }}
            </option>
            <option value="operational">
              {{ t('RELATIONSHIP.V2.DOCS.OPERATIONAL') }}
            </option>
            <option value="restricted">
              {{ t('RELATIONSHIP.V2.DOCS.RESTRICTED') }}
            </option>
          </select>
        </label>
        <DocumentRequirementField
          v-if="!document"
          v-model="form.requirement_key"
          :entries="requirements"
          :category="form.category"
          :disabled="busy"
        />
        <label class="block text-sm"
          >{{ t('RELATIONSHIP.V2.DOCS.FILE')
          }}<input
            type="file"
            required
            accept=".pdf,.png,.jpg,.jpeg,.txt,.docx"
            :class="inputClass"
            @change="file = $event.target.files[0]"
        /></label>
        <p class="text-sm text-n-slate-11">
          {{ t('RELATIONSHIP.V2.DOCS.QUARANTINE') }}
        </p>
      </div>
      <div
        v-show="tab === 'validity'"
        class="space-y-3"
      >
        <label class="block text-sm"
          >{{ t('RELATIONSHIP.V2.DOCS.VALID_UNTIL')
          }}<input
            v-model="form.valid_until"
            type="date"
            :class="inputClass" /></label
        ><label class="block text-sm"
          >{{ t('RELATIONSHIP.V2.DOCS.CHANGE_REASON')
          }}<textarea
            v-model="form.change_reason"
            required
            maxlength="500"
            :class="inputClass"
            rows="3"
          />
        </label>
      </div>
      <div class="flex justify-end gap-2">
        <button
          :class="buttonClass"
          type="button"
          :disabled="busy"
          @click="dialog.close()"
        >
          {{ t('RELATIONSHIP.CLOSE') }}</button
        ><button
          type="submit"
          class="rounded-lg bg-n-violet-9 px-4 py-2 font-semibold text-white disabled:opacity-50"
          :disabled="busy || !file"
        >
          {{ t(busy ? 'RELATIONSHIP.LOADING' : 'RELATIONSHIP.SAVE') }}
        </button>
      </div>
    </form>
  </Dialog>
</template>
