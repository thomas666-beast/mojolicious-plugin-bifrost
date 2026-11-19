import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';

export default defineConfig({
  plugins: [vue()],
  publicDir: false,
  base: './',
  build: {
    outDir: 'public/assets-demo',
    manifest: 'manifest.json',
    rollupOptions: { input: 'src/main.js' },
  },
});
