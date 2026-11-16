<script setup>
import { useRouter } from 'vue-router';

const props = defineProps({
  backUrl: {
    type: [String, Object],
    default: '',
  },
  buttonLabel: {
    type: String,
    default: '',
  },
  compact: {
    type: Boolean,
    default: false,
  },
});
const router = useRouter();
const goBack = () => {
  if (props.backUrl !== '') {
    router.push(props.backUrl);
  } else {
    router.go(-1);
  }
};

const buttonStyleClass = props.compact ? 'text-sm' : 'text-base';
</script>

<template>
  <button
    class="flex items-center p-0 font-normal cursor-pointer text-n-slate-11"
    :class="buttonStyleClass"
    @click.capture="goBack"
  >
    <i class="i-lucide-chevron-left -ml-1 text-lg" />
    {{ buttonLabel || $t('GENERAL_SETTINGS.BACK') }}
  </button>
</template>
