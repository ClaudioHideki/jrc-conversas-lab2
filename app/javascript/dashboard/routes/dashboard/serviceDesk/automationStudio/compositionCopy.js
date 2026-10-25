import { useI18n } from 'vue-i18n';
export const fieldClass =
  'w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12 disabled:opacity-50';
export const buttonClass =
  'rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm disabled:opacity-50';
export const primaryClass =
  'rounded-lg bg-n-blue-9 px-4 py-2 text-sm font-medium text-white disabled:opacity-50';
export const cardClass =
  'grid min-w-0 gap-3 rounded-xl border border-n-weak bg-n-solid-1 p-4';
export function useCompositionCopy() {
  const { t } = useI18n();
  return (key, values) =>
    t(`JRC_SERVICE_DESK.COORDINATED.${key}`, values || {});
}
