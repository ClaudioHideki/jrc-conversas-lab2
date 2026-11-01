const tones = {
  blue: [
    'border-blue-300 bg-blue-50 text-blue-800 hover:bg-blue-100 dark:border-blue-700 dark:bg-blue-950/60 dark:text-blue-200 dark:hover:bg-blue-900',
    'border-blue-600 bg-blue-600 text-white shadow-sm dark:border-blue-400 dark:bg-blue-600',
  ],
  teal: [
    'border-teal-300 bg-teal-50 text-teal-800 hover:bg-teal-100 dark:border-teal-700 dark:bg-teal-950/60 dark:text-teal-200 dark:hover:bg-teal-900',
    'border-teal-700 bg-teal-700 text-white shadow-sm dark:border-teal-400 dark:bg-teal-700',
  ],
  violet: [
    'border-violet-300 bg-violet-50 text-violet-800 hover:bg-violet-100 dark:border-violet-700 dark:bg-violet-950/60 dark:text-violet-200 dark:hover:bg-violet-900',
    'border-violet-700 bg-violet-700 text-white shadow-sm dark:border-violet-400 dark:bg-violet-600',
  ],
  amber: [
    'border-amber-300 bg-amber-50 text-amber-900 hover:bg-amber-100 dark:border-amber-700 dark:bg-amber-950/60 dark:text-amber-200 dark:hover:bg-amber-900',
    'border-amber-700 bg-amber-700 text-white shadow-sm dark:border-amber-400 dark:bg-amber-700',
  ],
  rose: [
    'border-rose-300 bg-rose-50 text-rose-800 hover:bg-rose-100 dark:border-rose-700 dark:bg-rose-950/60 dark:text-rose-200 dark:hover:bg-rose-900',
    'border-rose-700 bg-rose-700 text-white shadow-sm dark:border-rose-400 dark:bg-rose-600',
  ],
  cyan: [
    'border-cyan-300 bg-cyan-50 text-cyan-800 hover:bg-cyan-100 dark:border-cyan-700 dark:bg-cyan-950/60 dark:text-cyan-200 dark:hover:bg-cyan-900',
    'border-cyan-700 bg-cyan-700 text-white shadow-sm dark:border-cyan-400 dark:bg-cyan-700',
  ],
};

export const moduleTabClasses = (tone = 'blue', active = false) =>
  tones[tone][active ? 1 : 0];
