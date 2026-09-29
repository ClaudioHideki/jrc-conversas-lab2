<template>
  <div
    class="customer-360-panel bg-n-solid-2 border border-n-weak rounded-lg shadow-sm p-4"
  >
    <h3 class="font-semibold text-lg text-n-slate-12 mb-4 border-b pb-2">
      Visão 360
    </h3>

    <div v-if="contact" class="mb-4">
      <div class="flex items-center gap-3 mb-3">
        <div
          class="w-10 h-10 rounded-full bg-n-blue-3 text-n-blue-11 flex items-center justify-center font-bold text-lg"
        >
          {{ contact.name?.charAt(0) }}
        </div>
        <div>
          <div class="font-medium">{{ contact.name }}</div>
          <div class="text-xs text-n-slate-10">{{ contact.email }}</div>
        </div>
      </div>
      <div class="text-sm text-n-slate-11 flex flex-col gap-1">
        <div v-if="contact.phone_number">
          <i class="i-lucide-phone w-3 h-3 mr-1"></i>{{ contact.phone_number }}
        </div>
      </div>
    </div>

    <div v-if="company" class="mb-4 pt-3 border-t">
      <div class="font-medium text-sm text-n-slate-11 mb-1">
        <i class="i-lucide-building w-4 h-4 mr-1"></i>{{ company.name }}
      </div>
      <div class="text-xs text-n-slate-10" v-if="company.domain">
        {{ company.domain }}
      </div>
    </div>

    <OperationsLinks v-if="contact?.id" :contact-id="contact.id" compact />
    <div class="grid grid-cols-2 gap-2 mt-4 pt-3 border-t text-sm">
      <div class="bg-n-alpha-2 p-2 rounded text-center">
        <div class="text-xl font-bold text-n-blue-11">
          {{ metrics?.won_deals || 0 }}
        </div>
        <div class="text-xs text-n-slate-10 uppercase">Ganhos</div>
      </div>
      <div class="bg-n-alpha-2 p-2 rounded text-center">
        <div class="text-xl font-bold text-n-slate-12">
          {{ metrics?.open_deals || 0 }}
        </div>
        <div class="text-xs text-n-slate-10 uppercase">Abertos</div>
      </div>
    </div>
  </div>
</template>

<script setup>
import OperationsLinks from '../../../jrcOperations/components/OperationsLinks.vue';
defineProps({
  contact: Object,
  company: Object,
  metrics: Object,
});
</script>


