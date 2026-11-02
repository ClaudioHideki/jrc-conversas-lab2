import { computed, ref } from 'vue';
// Presentation only. Never unmount global call audio or change NICO permissions.
const editors = ref(0);
export const surveyModelEditorOpen = computed(() => editors.value > 0);
export function beginSurveyModelPresentation() {
  editors.value += 1;
  let released = false;
  return () => {
    if (!released) {
      released = true;
      editors.value = Math.max(0, editors.value - 1);
    }
  };
}
