import { computed, watch, onBeforeUnmount } from 'vue';
import { useStore } from 'vuex';
import { useRoute } from 'vue-router';
import { draftKey, readDraft, saveDraft, clearDraft } from './formDrafts';

export function useFormDraft(formType, { snapshot, restore, reset, active }) {
  const store = useStore();
  const route = useRoute();
  const key = computed(() => draftKey(route.params.accountId, store.getters.getCurrentUser?.id, typeof formType === 'function' ? formType() : formType));
  let timer;
  let paused = false;
  let saved = false;
  let completedSnapshot = '';
  const flush = () => {
    clearTimeout(timer);
    if (!paused && !saved && active.value) saveDraft(key.value, snapshot());
  };
  const open = () => {
    paused = true;
    saved = false;
    reset?.();
    const previous = readDraft(key.value);
    if (previous) restore(previous);
    paused = false;
    return Boolean(previous);
  };
  const discard = () => {
    clearTimeout(timer);
    paused = true;
    clearDraft(key.value);
    reset?.();
    paused = false;
    saved = false;
  };
  const complete = (savedKey = key.value) => {
    clearDraft(savedKey);
    if (savedKey !== key.value) return false;
    clearTimeout(timer);
    saved = true;
    completedSnapshot = JSON.stringify(snapshot());
    return true;
  };
  watch(snapshot, () => {
    if (paused || !active.value) return;
    if (saved && JSON.stringify(snapshot()) === completedSnapshot) return;
    saved = false;
    clearTimeout(timer);
    timer = setTimeout(flush, 300);
  }, { deep: true, flush: 'sync' });
  watch(active, (isOpen, wasOpen) => {
    if (!isOpen && wasOpen) {
      clearTimeout(timer);
      if (!saved && !paused) saveDraft(key.value, snapshot());
    }
  }, { flush: 'sync' });
  watch(key, (current, previous) => {
    clearTimeout(timer);
    if (previous && active.value && !saved) saveDraft(previous, snapshot());
    paused = true;
    reset?.();
    active.value = false;
    saved = false;
    paused = false;
  }, { flush: 'sync' });
  onBeforeUnmount(flush);
  return { key, open, discard, complete, flush };
}
