<script>
export default {
  props: {
    block: {
      type: Boolean,
      default: false,
    },
    type: {
      type: String,
      default: 'blue',
    },
    bgColor: {
      type: String,
      default: '',
    },
    textColor: {
      type: String,
      default: '',
    },
    disabled: {
      type: Boolean,
      default: false,
    },
  },
  computed: {
    buttonClassName() {
      let className =
        'text-white py-3 px-4 rounded-lg shadow-sm leading-4 cursor-pointer';
      if (this.type === 'clear') {
        className = 'flex mx-auto mt-4 text-xs leading-3 w-auto text-n-gray-12';
      }

      if (this.type === 'blue' && !Object.keys(this.buttonStyles).length) {
        className = `${className} bg-n-brand hover:enabled:brightness-110 focus-visible:ring-2 focus-visible:ring-n-blue-8 focus-visible:ring-offset-2`;
      }
      if (this.block) {
        className = `${className} w-full`;
      }
      return `${className} disabled:bg-n-slate-3 disabled:text-n-slate-11 disabled:opacity-100 disabled:cursor-not-allowed`;
    },
    buttonStyles() {
      const styles = {};
      if (this.disabled) return styles;
      if (this.bgColor) {
        styles.backgroundColor = this.bgColor;
      }
      if (this.textColor) {
        styles.color = this.textColor;
      }
      return styles;
    },
  },
};
</script>

<template>
  <button :class="buttonClassName" :style="buttonStyles" :disabled="disabled">
    <slot />
  </button>
</template>
