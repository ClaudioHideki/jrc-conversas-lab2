<script setup>
import { ref, watch } from 'vue';
import { moduleTabClasses } from './moduleTabClasses';

const props = defineProps({
  label: { type: String, required: true },
  items: { type: Array, required: true },
  groups: { type: Array, default: () => [] },
  activeKey: { type: String, required: true },
});
const navigation = ref(null);
const closeMenus = () => {
  navigation.value?.querySelectorAll('details[open]').forEach(menu => {
    menu.open = false;
  });
};
watch(() => props.activeKey, closeMenus);
</script>

<template>
  <nav
    ref="navigation"
    :aria-label="label"
    class="relative z-20 flex flex-wrap items-center gap-2 rounded-xl border border-n-weak bg-n-solid-2 p-2"
    @keydown.esc="closeMenus"
  >
    <RouterLink
      v-for="item in items"
      :key="item.key"
      :to="item.to"
      class="inline-flex items-center gap-2 whitespace-nowrap rounded-lg border px-3 py-2 text-sm font-semibold transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-blue-500"
      :class="moduleTabClasses(item.tone, activeKey === item.key)"
      :aria-current="activeKey === item.key ? 'page' : undefined"
    >
      <span
        :class="item.icon"
        class="size-4 shrink-0"
        aria-hidden="true"
      />
      {{ item.label }}
    </RouterLink>
    <details
      v-for="group in groups.filter(item => item.entries.length)"
      :key="group.key"
      class="static md:relative"
    >
      <summary
        class="flex cursor-pointer list-none items-center gap-2 whitespace-nowrap rounded-lg border px-3 py-2 text-sm font-semibold transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-blue-500 [&::-webkit-details-marker]:hidden"
        :class="
          moduleTabClasses(
            group.tone,
            group.entries.some(item => item.key === activeKey)
          )
        "
      >
        <span
          :class="group.icon"
          class="size-4 shrink-0"
          aria-hidden="true"
        />
        {{ group.label }}
        <span
          class="i-lucide-chevron-down size-3.5"
          aria-hidden="true"
        />
      </summary>
      <div
        class="absolute inset-x-0 top-full z-30 mt-2 grid max-h-80 gap-1 overflow-y-auto rounded-xl border border-n-strong bg-n-solid-2 p-2 shadow-lg md:left-auto md:right-0 md:min-w-64"
      >
        <RouterLink
          v-for="item in group.entries"
          :key="item.key"
          :to="item.to"
          class="flex items-center gap-2 rounded-lg border px-3 py-2.5 text-sm font-semibold"
          :class="
            moduleTabClasses(item.tone || group.tone, activeKey === item.key)
          "
          :aria-current="activeKey === item.key ? 'page' : undefined"
          @click="closeMenus"
        >
          <span
            :class="item.icon"
            class="size-4 shrink-0"
            aria-hidden="true"
          />
          {{ item.label }}
        </RouterLink>
      </div>
    </details>
  </nav>
</template>
