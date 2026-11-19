<script setup>
import { Head, Link, router } from '@inertiajs/vue3';
defineProps({ tasks: Object, loadedAt: String, appName: String });
</script>

<template>
  <Head title="Tasks" />
  <main>
    <header><span>{{ appName }}</span><Link href="/new">New task</Link></header>
    <h1>Tasks</h1>
    <ul>
      <li v-for="(task, index) in tasks.rows" :key="index">{{ task }}</li>
    </ul>
    <nav aria-label="Task pages">
      <Link v-if="tasks.page > 1" :href="`/?page=${tasks.page - 1}`" :only="['tasks']">Previous</Link>
      <span>Page {{ tasks.page }} of {{ tasks.pages }}</span>
      <Link v-if="tasks.page < tasks.pages" :href="`/?page=${tasks.page + 1}`" :only="['tasks']">Next</Link>
    </nav>
    <p class="note">Full page data loaded at: {{ loadedAt }} UTC</p>
    <button type="button" @click="router.reload({ only: ['tasks'] })">Refresh task list</button>
  </main>
</template>
