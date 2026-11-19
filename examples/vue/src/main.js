import { createApp, h } from 'vue';
import { createInertiaApp } from '@inertiajs/vue3';
import Tasks from './pages/Tasks.vue';
import Create from './pages/Create.vue';
import './style.css';

const pages = { Tasks, Create };

createInertiaApp({
  resolve: (name) => pages[name],
  setup({ el, App, props, plugin }) {
    createApp({ render: () => h(App, props) }).use(plugin).mount(el);
  },
});
