import base from '../../vitest.config';

// Functional component tests do not need the application's Tailwind/PostCSS pipeline.
// No production build configuration is changed by this isolated test configuration.
export default {
  ...base,
  css: { postcss: { plugins: [] } },
  test: {
    ...base.test,
    include: [
      'app/javascript/dashboard/routes/dashboard/webphone/**/*.spec.js',
      'app/javascript/dashboard/components-next/layout/SoftphoneDownload.spec.js',
      'desktop/test/floating.integration.spec.js',
    ],
  },
};
