import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';
import { aliases, vueOptions } from '../../../../vite.shared';

export default defineConfig({
  plugins: [vue(vueOptions)],
  resolve: { alias: aliases },
  server: { host: '127.0.0.1', port: 5214, strictPort: true },
});
