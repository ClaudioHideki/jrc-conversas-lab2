<script setup>
defineProps({ name: { type: String, default: 'document' } });
const paths = {
  home: 'm3 10 9-7 9 7M5 9v12h5v-7h4v7h5V9',
  plus: 'M12 8v8M8 12h8M22 12a10 10 0 1 1-20 0 10 10 0 0 1 20 0Z',
  headset:
    'M4 13v-2a8 8 0 0 1 16 0v2M4 12H3v7h4v-7H4Zm16 0h1v7h-4v-7h3Zm0 7c0 3-4 3-7 3',
  book: 'M12 5v16M12 5C8 2 4 3 2 4v15c4-2 7-1 10 2 3-3 6-4 10-2V4c-3-1-6-2-10 1Z',
  user: 'M16 7a4 4 0 1 1-8 0 4 4 0 0 1 8 0ZM4 21v-2a8 8 0 0 1 16 0v2H4Z',
  document: 'M14 2H5v20h14V7l-5-5Zm0 0v6h5M8 12h8M8 16h8',
  building:
    'M4 22V3h12v19M16 10h5v12M8 7h1m3 0h1M8 11h1m3 0h1M8 15h1m3 0h1M9 22v-3h3v3',
  mail: 'M3 5h18v14H3V5Zm0 0 9 8 9-8',
  phone: 'M7 3H3c-1 9 8 18 18 18v-5l-5-2-3 3c-3-1-5-3-6-6l3-3-3-5Z',
  calendar: 'M5 3v4M19 3v4M3 10h18M3 5h18v16H3V5ZM7 14h3m4 0h3M7 17h3',
  search: 'M17 17l5 5M19 10a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z',
  clock: 'M12 6v6l4 2M22 12a10 10 0 1 1-20 0 10 10 0 0 1 20 0Z',
  check: 'm7 12 3 3 7-7M22 12a10 10 0 1 1-20 0 10 10 0 0 1 20 0Z',
  info: 'M12 10v7m0-10v.1M22 12a10 10 0 1 1-20 0 10 10 0 0 1 20 0Z',
  clip: 'm8 13 8-8a4 4 0 0 1 6 6L10 23a6 6 0 0 1-8-8L14 3m-9 15a2 2 0 0 0 3 3L19 10',
  send: 'm2 3 20 9-20 9 4-9-4-9Zm4 9h16',
  logout: 'M9 3H3v18h6M9 12h13m-5-5 5 5-5 5',
};
</script>

<template>
  <svg
    viewBox="0 0 24 24"
    width="24"
    height="24"
    fill="none"
    stroke="currentColor"
    stroke-width="1.8"
    stroke-linecap="round"
    stroke-linejoin="round"
    aria-hidden="true"
    class="shrink-0"
  >
    <path :d="paths[name] || paths.document" />
  </svg>
</template>
