<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import NextButton from 'dashboard/components-next/button/Button.vue';

const emit = defineEmits(['select']);

const store = useStore();
const getters = useStoreGetters();

const isOpen = ref(false);
const searchQuery = ref('');

const cannedResponses = computed(() => {
  return getters['cannedResponse/getCannedResponses'].value || [];
});

const filteredResponses = computed(() => {
  const query = searchQuery.value.trim().toLowerCase();
  if (!query) return cannedResponses.value;
  return cannedResponses.value.filter(item => {
    const matchCode = (item.short_code || '').toLowerCase().includes(query);
    const matchContent = (item.content || '').toLowerCase().includes(query);
    return matchCode || matchContent;
  });
});

onMounted(() => {
  if (!cannedResponses.value.length) {
    store.dispatch('cannedResponse/get');
  }
});

const toggleOpen = () => {
  isOpen.value = !isOpen.value;
  if (isOpen.value) {
    searchQuery.value = '';
    if (!cannedResponses.value.length) {
      store.dispatch('cannedResponse/get');
    }
  }
};

const close = () => {
  isOpen.value = false;
};

const selectResponse = item => {
  emit('select', item.content);
  close();
};
</script>

<template>
  <div class="relative">
    <NextButton
      v-tooltip.top-end="'常用话术库 (快捷回复)'"
      icon="i-ph-lightning"
      slate
      faded
      sm
      @click="toggleOpen"
    />

    <!-- Popover -->
    <div
      v-if="isOpen"
      v-on-clickaway="close"
      class="absolute bottom-10 left-0 w-80 max-h-96 rounded-xl bg-white dark:bg-n-solid-2 border border-n-strong shadow-2xl z-50 flex flex-col overflow-hidden animate-in fade-in zoom-in-95 duration-100"
    >
      <!-- Header & Search -->
      <div class="p-3 border-b border-n-strong bg-n-slate-2 dark:bg-n-solid-1">
        <div class="flex items-center justify-between mb-2">
          <span class="text-xs font-bold text-n-slate-12 flex items-center gap-1.5">
            <span class="i-ph-lightning size-3.5 text-n-brand" />
            常用话术快捷库
          </span>
          <span class="text-[11px] text-n-slate-10 font-medium">点击直接填入</span>
        </div>
        <div class="relative">
          <span class="absolute i-lucide-search size-3.5 left-2.5 top-2.5 text-n-slate-10" />
          <input
            v-model="searchQuery"
            type="text"
            class="w-full text-xs rounded-lg pl-8 pr-2.5 py-1.5 border border-n-strong bg-white dark:bg-n-solid-2 text-n-slate-12 focus:ring-2 focus:ring-n-brand/30"
            placeholder="搜索短语代号或话术内容..."
            autofocus
          />
        </div>
      </div>

      <!-- List of canned responses -->
      <div class="overflow-y-auto flex-1 p-1 max-h-64 divide-y divide-n-weak">
        <div
          v-for="item in filteredResponses"
          :key="item.id"
          class="p-2.5 hover:bg-n-slate-2 dark:hover:bg-n-solid-3 rounded-lg cursor-pointer transition-colors text-left group"
          @click="selectResponse(item)"
        >
          <div class="flex items-center justify-between mb-1">
            <span class="text-xs font-bold text-n-brand bg-n-brand/10 dark:bg-n-brand/20 px-1.5 py-0.5 rounded text-[11px]">
              /{{ item.short_code }}
            </span>
            <span class="text-[10px] text-n-slate-10 opacity-0 group-hover:opacity-100 transition-opacity">
              点击填入 ↵
            </span>
          </div>
          <p class="text-xs text-n-slate-12 line-clamp-2 leading-relaxed">
            {{ item.content }}
          </p>
        </div>

        <div
          v-if="!filteredResponses.length"
          class="py-8 text-center text-xs text-n-slate-10 flex flex-col items-center justify-center gap-1"
        >
          <span class="i-lucide-message-square-off size-6 text-n-slate-9 mb-1" />
          <span>{{ searchQuery ? '未找到匹配的快捷话术' : '暂无预设快捷话术' }}</span>
          <span class="text-[11px]">可在 设置 ➔ 快捷回复 中添加管理</span>
        </div>
      </div>
    </div>
  </div>
</template>
