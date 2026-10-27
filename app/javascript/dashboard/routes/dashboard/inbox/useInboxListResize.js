import { computed, ref, watch } from 'vue';
import { useElementSize, useWindowSize } from '@vueuse/core';

const WIDTHS = {
  192: 'xl:w-48',
  208: 'xl:w-52',
  224: 'xl:w-56',
  240: 'xl:w-60',
  256: 'xl:w-64',
  272: 'xl:w-[272px]',
  288: 'xl:w-72',
  304: 'xl:w-[304px]',
  320: 'xl:w-80',
  336: 'xl:w-[336px]',
  352: 'xl:w-[352px]',
  368: 'xl:w-[368px]',
  384: 'xl:w-96',
  400: 'xl:w-[400px]',
  416: 'xl:w-[416px]',
  432: 'xl:w-[432px]',
  448: 'xl:w-[448px]',
  464: 'xl:w-[464px]',
  480: 'xl:w-[480px]',
};
const MIN = 192;
const MAX = 480;
const STEP = 16;

export function useInboxListResize(
  accountId,
  userId,
  layout,
  customerColumn,
  list
) {
  const { width: viewport } = useWindowSize();
  const { width: layoutWidth } = useElementSize(layout);
  const { width: customerWidth } = useElementSize(customerColumn);
  const preferred = ref(null);
  const dragging = ref(false);
  const storageKey = computed(() =>
    accountId.value && userId.value
      ? `jrc:attendance-list-width:${accountId.value}:${userId.value}`
      : ''
  );
  const defaultWidth = computed(() => (viewport.value >= 1536 ? 240 : 224));
  const maxWidth = computed(() =>
    layoutWidth.value
      ? Math.max(
          MIN,
          Math.min(
            MAX,
            Math.floor((layoutWidth.value - customerWidth.value - 392) / STEP) *
              STEP
          )
        )
      : MAX
  );
  const clamp = value =>
    Math.max(MIN, Math.min(maxWidth.value, Math.round(value / STEP) * STEP));
  const width = computed(() => clamp(preferred.value ?? defaultWidth.value));
  const widthClass = computed(() => WIDTHS[width.value]);
  let drag = null;
  const persist = () => {
    if (!storageKey.value) return;
    try {
      if (preferred.value === null) localStorage.removeItem(storageKey.value);
      else localStorage.setItem(storageKey.value, String(preferred.value));
    } catch {
      /* A browser preference must not interrupt attendance. */
    }
  };
  watch(
    storageKey,
    key => {
      dragging.value = false;
      drag = null;
      preferred.value = null;
      if (!key) return;
      try {
        const saved = localStorage.getItem(key);
        const value = Number(saved);
        if (
          saved !== null &&
          Number.isFinite(value) &&
          value >= MIN &&
          value <= MAX
        )
          preferred.value = Math.round(value / STEP) * STEP;
      } catch {
        /* Keep the responsive default when storage is unavailable. */
      }
    },
    { immediate: true, flush: 'sync' }
  );
  const direction = () =>
    list.value && getComputedStyle(list.value).direction === 'rtl' ? -1 : 1;
  const start = event => {
    if (event.button !== 0 || viewport.value < 1280) return;
    event.preventDefault();
    drag = {
      x: event.clientX,
      width: width.value,
      direction: direction(),
      key: storageKey.value,
    };
    dragging.value = true;
    event.currentTarget.setPointerCapture?.(event.pointerId);
  };
  const move = event => {
    if (!drag || drag.key !== storageKey.value || viewport.value < 1280) return;
    preferred.value = clamp(
      drag.width + (event.clientX - drag.x) * drag.direction
    );
  };
  const end = () => {
    if (!drag) return;
    if (drag.key === storageKey.value) persist();
    drag = null;
    dragging.value = false;
  };
  const reset = () => {
    preferred.value = null;
    drag = null;
    dragging.value = false;
    persist();
  };
  const keydown = event => {
    const keys = ['ArrowLeft', 'ArrowRight', 'Home', 'End', 'Enter'];
    if (!keys.includes(event.key)) return;
    event.preventDefault();
    if (event.key === 'Enter') {
      reset();
      return;
    }
    if (event.key === 'Home') preferred.value = MIN;
    else if (event.key === 'End') preferred.value = maxWidth.value;
    else
      preferred.value = clamp(
        width.value +
          (event.key === 'ArrowRight' ? 1 : -1) *
            direction() *
            STEP *
            (event.shiftKey ? 4 : 1)
      );
    persist();
  };
  return {
    width,
    widthClass,
    minWidth: MIN,
    maxWidth,
    dragging,
    start,
    move,
    end,
    reset,
    keydown,
  };
}
