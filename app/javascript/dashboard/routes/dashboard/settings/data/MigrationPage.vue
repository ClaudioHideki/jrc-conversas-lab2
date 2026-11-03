<script setup>
import { useAccount } from 'dashboard/composables/useAccount';
import { useAdmin } from 'dashboard/composables/useAdmin';
import MigrationCenter from './MigrationCenter.vue';
const { accountId } = useAccount();
const { isAdmin } = useAdmin();
</script>

<template>
  <MigrationCenter v-if="isAdmin" :key="accountId" :account-id="accountId" />
</template>
