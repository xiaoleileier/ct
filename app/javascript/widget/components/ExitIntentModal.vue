<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue';

const emit = defineEmits(['close']);

const isVisible = ref(false);

const tgUrl = computed(() => {
  const customUrl = window.chatwootWebChannel?.telegramGroupUrl;
  return customUrl && customUrl.trim() ? customUrl.trim() : 'https://t.me/';
});

const handleMouseLeave = e => {
  if (e.clientY <= 12) {
    checkAndShow();
  }
};

const checkAndShow = () => {
  if (sessionStorage.getItem('cw_exit_intent_shown')) return;
  isVisible.value = true;
  sessionStorage.setItem('cw_exit_intent_shown', 'true');
};

const close = () => {
  isVisible.value = false;
  emit('close');
};

const handleJoinTelegram = () => {
  close();
  if (tgUrl.value) {
    window.open(tgUrl.value, '_blank', 'noopener,noreferrer');
  }
};

const handleContinueChat = () => {
  close();
  const input = document.getElementById('chat-input');
  if (input) input.focus();
};

let waitTimer = null;

onMounted(() => {
  document.addEventListener('mouseleave', handleMouseLeave);
  // 用户在聊天窗口停留或等待 60 秒后，自动提醒一次防失联加群
  waitTimer = setTimeout(() => {
    checkAndShow();
  }, 60000);
});

onUnmounted(() => {
  document.removeEventListener('mouseleave', handleMouseLeave);
  if (waitTimer) clearTimeout(waitTimer);
});
</script>

<template>
  <div
    v-if="isVisible"
    class="absolute inset-0 z-50 flex items-center justify-center p-4 bg-black/40 backdrop-blur-xs animate-in fade-in duration-200"
  >
    <div
      class="w-full max-w-xs bg-white dark:bg-n-solid-2 rounded-2xl p-5 shadow-2xl border border-n-weak flex flex-col items-center text-center relative zoom-in-95 duration-200"
    >
      <button
        type="button"
        class="absolute top-3 right-3 text-n-slate-9 hover:text-n-slate-12 p-1 rounded-full cursor-pointer transition-colors"
        @click="close"
      >
        <span class="i-lucide-x size-4" />
      </button>

      <div class="size-12 rounded-full bg-sky-500/10 flex items-center justify-center text-sky-500 mb-3 shadow-xs">
        <span class="i-lucide-send size-6" />
      </div>

      <h3 class="text-base font-bold text-n-slate-12 mb-1.5 flex items-center justify-center gap-1.5">
        <span>防失联 & 官方服务群提醒</span>
      </h3>
      <p class="text-xs text-n-slate-10 leading-relaxed mb-4 text-center">
        客服已收到您的咨询正在加紧为您接入。为防网页关闭后失联，建议您提前加入官方 Telegram 交流群，实时获取最新节点维护公告与备用域名！
      </p>

      <div class="flex flex-col gap-2 w-full">
        <button
          type="button"
          class="w-full py-2.5 px-3 rounded-xl bg-sky-500 hover:bg-sky-600 text-white font-medium text-xs shadow-md shadow-sky-500/20 transition-all cursor-pointer flex items-center justify-center gap-1.5"
          @click="handleJoinTelegram"
        >
          <span class="i-lucide-send size-3.5" />
          👉 加入 Telegram 官方群 / 频道
        </button>
        <button
          type="button"
          class="w-full py-2 px-3 rounded-xl border border-n-weak bg-n-slate-2 dark:bg-n-solid-3 text-n-slate-11 hover:text-n-slate-12 text-xs font-medium transition-all cursor-pointer"
          @click="handleContinueChat"
        >
          留在本页继续等待客服
        </button>
      </div>
    </div>
  </div>
</template>
