import base from './vitest.config';

export default {
  ...base,
  css: { postcss: { plugins: [] } },
  test: {
    ...base.test,
    maxWorkers: 1,
    minWorkers: 1,
    include: [
      'app/javascript/dashboard/routes/dashboard/contacts/**/spec/*.spec.js',
      'app/javascript/dashboard/routes/dashboard/crm/**/*.spec.js',
      'app/javascript/dashboard/api/specs/contacts.spec.js',
      'app/javascript/dashboard/api/crm/spec/*.spec.js',
      'app/javascript/dashboard/store/modules/specs/contacts/*.spec.js',
    ],
  },
};
