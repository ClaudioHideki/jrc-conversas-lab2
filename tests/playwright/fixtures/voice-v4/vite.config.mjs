import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';
import yaml from '@rollup/plugin-yaml';
import { fileURLToPath } from 'node:url';
import { aliases, vueOptions } from '../../../../vite.shared';
const fixture = name => fileURLToPath(new URL(name, import.meta.url));
export default defineConfig({
  publicDir: false,
  plugins: [vue(vueOptions), yaml()],
  resolve: {
    alias: [
      {
        find: /^dashboard\/routes\/dashboard\/webphone\/useSipWebphone$/,
        replacement: fixture('./state.js'),
      },
      {
        find: /^\.\.\/webphone\/useSipWebphone$/,
        replacement: fixture('./state.js'),
      },
      {
        find: /^dashboard\/api\/jrcContactCenter$/,
        replacement: fixture('./api.js'),
      },
      {
        find: /^dashboard\/api\/contacts$/,
        replacement: fixture('./contacts.js'),
      },
      {
        find: /^dashboard\/components-next\/layout\/useQuickActionAccess$/,
        replacement: fixture('./access.js'),
      },
      {
        find: /^\.\/useQuickActionAccess$/,
        replacement: fixture('./access.js'),
      },
      {
        find: /^dashboard\/stores\/calls$/,
        replacement: fixture('./state.js'),
      },
      {
        find: /^dashboard\/composables\/useWhatsappCallSession$/,
        replacement: fixture('./state.js'),
      },
      ...Object.entries(aliases).map(([find, replacement]) => ({
        find,
        replacement,
      })),
    ],
  },
  server: {
    host: '127.0.0.1',
    port: Number(process.env.JRC_VOICE_FIXTURE_PORT || 5226),
    strictPort: true,
  },
  preview: {
    host: '127.0.0.1',
    port: Number(process.env.JRC_VOICE_FIXTURE_PORT || 5226),
    strictPort: true,
  },
  build: {
    outDir: '.codex/atendimento-voz-20261110-static',
    rollupOptions: { input: fixture('./index.html') },
  },
});
