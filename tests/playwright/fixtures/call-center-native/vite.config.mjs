import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';
import yaml from '@rollup/plugin-yaml';
import { fileURLToPath } from 'node:url';
import { aliases, vueOptions } from '../../../../vite.shared';
const local = value => fileURLToPath(new URL(value, import.meta.url));
export default defineConfig({
  root: local('./'),
  publicDir: false,
  plugins: [vue(vueOptions), yaml()],
  resolve: { alias: aliases },
  preview: {
    host: '127.0.0.1',
    port: 5386,
    strictPort: true,
    proxy: { '/api': 'http://127.0.0.1:5387' },
  },
  build: {
    outDir: local('../../../../.codex/call-center-native-static'),
    emptyOutDir: false,
  },
});
