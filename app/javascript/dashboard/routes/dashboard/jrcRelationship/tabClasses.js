import { moduleTabClasses } from 'dashboard/components-next/navigation/moduleTabClasses';
export const relationshipTabClasses = (tone, active) => {
  if (tone !== 'violet') return moduleTabClasses(tone, active);
  return active
    ? 'border-n-violet-9 bg-n-violet-9 text-white shadow-sm'
    : 'border-n-violet-6 bg-n-violet-2 text-n-violet-11 hover:bg-n-violet-3';
};
