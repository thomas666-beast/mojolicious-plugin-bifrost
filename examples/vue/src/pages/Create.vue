<script setup>
import { Head, Link, useForm } from '@inertiajs/vue3';
const props = defineProps({ csrfToken: String, appName: String });
const form = useForm({ title: '' });
</script>

<template>
  <Head title="New task" />
  <main>
    <header><span>{{ appName }}</span><Link href="/">Back to tasks</Link></header>
    <h1>New task</h1>
    <form @submit.prevent="form.post('/tasks', { headers: { 'X-CSRF-Token': props.csrfToken } })">
      <label for="title">Task title</label>
      <input id="title" v-model="form.title" :aria-invalid="Boolean(form.errors.title)"
             :aria-describedby="form.errors.title ? 'title-error' : undefined">
      <p v-if="form.errors.title" id="title-error" role="alert">{{ form.errors.title }}</p>
      <button type="submit" :disabled="form.processing">Add task</button>
    </form>
  </main>
</template>
