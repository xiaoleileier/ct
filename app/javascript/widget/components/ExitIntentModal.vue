<script setup>
import { ref, onMounted, onUnmounted } from 'vue';
import { useStore } from 'vuex';

const emit = defineEmits(['close']);
const store = useStore();

const isVisible = ref(false);

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

const handleLeaveContact = () => {
  close();
  // Fill prompt into chat input if possible
  const input = document.getElementById('chat-input');
  if (input) {
    input.value = '我的联系方式是: ';
    input.focus();
    input.dispatchEvent(new Event('input', { bubbles: true }));
  }
};

const handleContinueChat = () => {
  close();
  const input = document.getElementById('chat-input');
  if (input) input.focus();
};

onMounted(() => {
  document.addEventListener('mouseleave', handleMouseLeave);
});

onUnmounted(() => {
  document.removeEventListener('mouseleave', handleMouseLeave);
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
        class="absolute top-3 right-3 text-n-slate-9 hover:text-n-slate-12 p-1 rounded-full cursor-pointer"
        @click="close"
      >
        <span class="i-lucide-x size-4" />
      </button>

      <div class="size-12 rounded-full bg-amber-500/10 flex items-center justify-center text-amber-500 mb-3">
        <span class="i-lucide-gift size-6" />
      </div>

      <h3 class="text-base font-bold text-n-slate-12 mb-1.5">
        别急着走，为您准备了专属福利！
      </h3>
      <p class="text-xs text-n-slate-10 leading-relaxed mb-4">
        客服目前在线，可为您提供快速方案报价。您也可以留下微信号或电话，稍后我们为您送上专享资料与优惠。
      </p>

      <div class="flex flex-col gap-2 w-full">
        <button
          type="button"
          class="w-full py-2 px-3 rounded-xl bg-n-brand text-white font-medium text-xs hover:opacity-90 shadow-md transition-all cursor-pointer flex items-center justify-center gap-1.5"
          @click="handleLeaveContact"
        >
          <span class="i-lucide-message-circle size-3.5" />
          留下微信 / 手机号
        </button>
        <button
          type="button"
          class="w-full py-2 px-3 rounded-xl border border-n-weak bg-n-slate-2 dark:bg-n-solid-3 text-n-slate-11 hover:text-n-slate-12 text-xs font-medium transition-all cursor-pointer"
          @click="handleContinueChat"
        >
          继续咨询客服
        </button>
      </div>
    </div>
  </div>
</template>
