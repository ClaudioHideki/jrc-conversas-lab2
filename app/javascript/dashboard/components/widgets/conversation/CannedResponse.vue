<script>
import { mapGetters } from 'vuex';
import MentionBox from '../mentions/MentionBox.vue';

export default {
  components: { MentionBox },
  props: {
    reviewBeforeInsert: { type: Boolean, default: false },
    searchKey: {
      type: String,
      default: '',
    },
  },
  emits: ['replace', 'review'],
  computed: {
    ...mapGetters({
      cannedMessages: 'getCannedResponses',
      accountId: 'getCurrentAccountId',
    }),
    items() {
      return this.cannedMessages
        .filter(
          row =>
            !this.reviewBeforeInsert ||
            String(row.account_id) === String(this.accountId)
        )
        .map(cannedMessage => ({
          id: cannedMessage.id,
          label: cannedMessage.short_code,
          key: cannedMessage.short_code,
          description: cannedMessage.content,
        }));
    },
  },
  watch: {
    searchKey() {
      this.fetchCannedResponses();
    },
  },
  mounted() {
    this.fetchCannedResponses();
  },
  methods: {
    fetchCannedResponses() {
      this.$store.dispatch('getCannedResponse', { searchKey: this.searchKey });
    },
    handleMentionClick(item = {}) {
      if (this.reviewBeforeInsert) this.$emit('review', item.id);
      else this.$emit('replace', item.description);
    },
  },
};
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <MentionBox
    v-if="items.length"
    :items="items"
    @mention-select="handleMentionClick"
  />
</template>
