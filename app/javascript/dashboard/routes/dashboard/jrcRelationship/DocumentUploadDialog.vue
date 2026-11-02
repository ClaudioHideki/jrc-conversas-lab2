<script setup>
import { onMounted, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { buttonClass, inputClass } from './definitions';
const props = defineProps({
  document: { type: Object, default: null },
  busy: Boolean,
  error: { type: String, default: '' },
});
const emit = defineEmits(['close', 'save']);
const { t } = useI18n();
const dialog = ref(null);
const tab = ref('file');
const form = reactive({
  title: props.document?.title || '',
  category: props.document?.category || 'registration',
  valid_until: '',
  change_reason: '',
});
const file = ref(null);
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
        ><label class="block text-sm"
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
