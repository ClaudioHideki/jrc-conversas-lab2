<script setup>
import BackButton from 'dashboard/components/widgets/BackButton.vue';

defineProps({
  headerTitle: {
    required: true,
    type: String,
  },
  headerDescription: {
    type: String,
    default: '',
  },
  hasBackButton: {
    type: Boolean,
    default: false,
  },
  icon: { type: String, default: 'i-lucide-chart-column-increasing' },
  accent: { type: String, default: 'blue' },
});
const accents = {
  blue: 'border-n-blue-5 from-n-blue-3 text-n-blue-11',
  violet: 'border-n-violet-5 from-n-violet-3 text-n-violet-11',
  teal: 'border-n-teal-5 from-n-teal-3 text-n-teal-11',
  amber: 'border-n-amber-5 from-n-amber-3 text-n-amber-11',
  ruby: 'border-n-ruby-5 from-n-ruby-3 text-n-ruby-11',
};
</script>

<template>
  <section class="mb-5 mt-4 space-y-3">
    <div v-if="hasBackButton">
      <BackButton compact />
    </div>
    <div
      class="flex flex-col gap-4 rounded-2xl border bg-gradient-to-br to-n-solid-1 px-4 py-4 shadow-sm sm:flex-row sm:items-center sm:justify-between sm:px-6"
      :class="accents[accent]"
    >
      <div class="flex min-w-0 items-start gap-3 sm:items-center">
        <span
          class="grid size-11 shrink-0 place-items-center rounded-xl bg-n-solid-1 shadow-sm"
          aria-hidden="true"
        >
          <span class="size-5" :class="icon" />
        </span>
        <div class="min-w-0">
          <h2
            class="m-0 text-xl font-semibold tracking-tight text-n-slate-12 sm:text-2xl"
          >
            {{ headerTitle }}
          </h2>
          <p
            v-if="headerDescription"
            class="mb-0 mt-1 max-w-2xl text-sm leading-relaxed text-n-slate-11"
          >
            {{ headerDescription }}
          </p>
        </div>
      </div>
      <div v-if="$slots.default" class="shrink-0">
        <slot />
      </div>
    </div>
  </section>
</template>
