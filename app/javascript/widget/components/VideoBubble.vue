<script setup>
import { computed } from 'vue';

const props = defineProps({
  url: { type: String, default: '' },
  readableTime: { type: String, default: '' },
});

const emit = defineEmits(['error']);

const onVideoError = () => {
  emit('error');
};

const isAnimation = computed(() => {
  const lowerUrl = (props.url || '').toLowerCase();
  return (
    lowerUrl.includes('animation') ||
    lowerUrl.includes('.gif') ||
    lowerUrl.includes('giphy') ||
    lowerUrl.includes('tenor')
  );
});
</script>

<template>
  <div class="relative block max-w-full">
    <video
      class="w-full max-w-[250px] h-auto rounded-lg"
      :src="url"
      controls
      :autoplay="isAnimation"
      :loop="isAnimation"
      :muted="isAnimation"
      playsinline
      @error="onVideoError"
    />
    <span
      class="absolute text-xs text-white dark:text-white right-3 bottom-1 whitespace-nowrap"
    >
      {{ readableTime }}
    </span>
  </div>
</template>
