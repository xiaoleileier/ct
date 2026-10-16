<script setup>
import { computed, onUnmounted } from 'vue';
import { useToggle } from '@vueuse/core';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import { emitter } from 'shared/helpers/mitt';
import EmailTranscriptModal from './EmailTranscriptModal.vue';
import ResolveAction from '../../buttons/ResolveAction.vue';
import ButtonV4 from 'dashboard/components-next/button/Button.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';

import {
  CMD_MUTE_CONVERSATION,
  CMD_SEND_TRANSCRIPT,
  CMD_UNMUTE_CONVERSATION,
} from 'dashboard/helper/commandbar/events';

// No props needed as we're getting currentChat from the store directly
const store = useStore();
const { t } = useI18n();

const [showEmailActionsModal, toggleEmailModal] = useToggle(false);
const [showActionsDropdown, toggleDropdown] = useToggle(false);

const currentChat = computed(() => store.getters.getSelectedChat);

const actionMenuItems = computed(() => {
  const items = [];

  if (!currentChat.value.muted) {
    items.push({
      icon: 'i-lucide-volume-off',
      label: t('CONTACT_PANEL.MUTE_CONTACT'),
      action: 'mute',
      value: 'mute',
    });
  } else {
    items.push({
      icon: 'i-lucide-volume-1',
      label: t('CONTACT_PANEL.UNMUTE_CONTACT'),
      action: 'unmute',
      value: 'unmute',
    });
  }

  items.push({
    icon: 'i-lucide-share',
    label: t('CONTACT_PANEL.SEND_TRANSCRIPT'),
    action: 'send_transcript',
    value: 'send_transcript',
  });

  items.push({
    icon: 'i-lucide-file-text',
    label: '导出聊天记录 (TXT文本)',
    action: 'export_txt',
    value: 'export_txt',
  });

  items.push({
    icon: 'i-lucide-printer',
    label: '打印 / 导出为 PDF',
    action: 'print_pdf',
    value: 'print_pdf',
  });

  return items;
});

const exportTxt = () => {
  const chat = currentChat.value;
  const messages = chat.messages || [];
  const sender = chat.meta?.sender || {};
  let content = `========================================\n`;
  content += `会话编号: #${chat.id}\n`;
  content += `客户姓名: ${sender.name || '访客'}\n`;
  content += `客户电话: ${sender.phone_number || '-'}\n`;
  content += `客户邮箱: ${sender.email || '-'}\n`;
  content += `会话标签: ${(chat.labels || []).join(', ') || '-'}\n`;
  content += `导出时间: ${new Date().toLocaleString()}\n`;
  content += `========================================\n\n`;

  messages.forEach(msg => {
    const time = new Date(msg.created_at * 1000).toLocaleString();
    const isIncoming = msg.message_type === 0;
    const senderName =
      msg.sender?.name || (isIncoming ? '客户' : '客服');
    const role = isIncoming
      ? '[客户]'
      : msg.private
        ? '[私有备注]'
        : '[客服回复]';
    content += `${time} ${role} ${senderName}:\n${msg.content || '[附件/卡片]'}\n\n`;
  });

  const blob = new Blob([content], { type: 'text/plain;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = `会话记录_#${chat.id}_${sender.name || '访客'}.txt`;
  a.click();
  URL.revokeObjectURL(url);
  useAlert('聊天记录已导出为 TXT 文件！');
};

const printPdf = () => {
  const chat = currentChat.value;
  const messages = chat.messages || [];
  const sender = chat.meta?.sender || {};

  const printWindow = window.open('', '_blank');
  if (!printWindow) return;

  const rows = messages
    .map(msg => {
      const time = new Date(msg.created_at * 1000).toLocaleString();
      const isIncoming = msg.message_type === 0;
      const senderName =
        msg.sender?.name || (isIncoming ? '客户' : '客服');
      const bgClass = isIncoming
        ? 'background: #f1f5f9;'
        : msg.private
          ? 'background: #fef3c7;'
          : 'background: #eff6ff;';
      const alignClass = isIncoming
        ? 'text-align: left;'
        : 'text-align: right;';
      return `
      <div style="margin-bottom: 12px; ${alignClass}">
        <div style="font-size: 11px; color: #64748b; margin-bottom: 3px;">
          ${senderName} · ${time} ${msg.private ? '(私有备注)' : ''}
        </div>
        <div style="display: inline-block; max-width: 75%; padding: 8px 14px; border-radius: 10px; font-size: 13px; text-align: left; line-height: 1.5; ${bgClass}">
          ${(msg.content || '[附件]').replace(/\n/g, '<br/>')}
        </div>
      </div>
    `;
    })
    .join('');

  printWindow.document.write(`
    <!DOCTYPE html>
    <html>
      <head>
        <title>会话记录 - #${chat.id} - ${sender.name || '客户'}</title>
        <style>
          body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; padding: 24px; color: #0f172a; }
          .header { border-bottom: 2px solid #e2e8f0; padding-bottom: 16px; margin-bottom: 24px; }
          .title { font-size: 20px; font-weight: bold; margin-bottom: 8px; }
          .meta { font-size: 12px; color: #475569; display: grid; grid-template-columns: 1fr 1fr; gap: 6px; }
          @media print {
            body { padding: 0; }
          }
        </style>
      </head>
      <body>
        <div class="header">
          <div class="title">Chatwoot 客户沟通记录 (#${chat.id})</div>
          <div class="meta">
            <div>客户姓名: <strong>${sender.name || '访客'}</strong></div>
            <div>导出时间: ${new Date().toLocaleString()}</div>
            <div>联系电话: ${sender.phone_number || '-'}</div>
            <div>电子邮箱: ${sender.email || '-'}</div>
            <div>会话标签: ${(chat.labels || []).join(', ') || '-'}</div>
          </div>
        </div>
        <div class="messages">
          ${rows}
        </div>
        <script>
          window.onload = function() {
            setTimeout(function() {
              window.print();
            }, 300);
          };
        <\/script>
      </body>
    </html>
  `);
  printWindow.document.close();
};

const handleActionClick = ({ action }) => {
  toggleDropdown(false);

  if (action === 'mute') {
    store.dispatch('muteConversation', currentChat.value.id);
    useAlert(t('CONTACT_PANEL.MUTED_SUCCESS'));
  } else if (action === 'unmute') {
    store.dispatch('unmuteConversation', currentChat.value.id);
    useAlert(t('CONTACT_PANEL.UNMUTED_SUCCESS'));
  } else if (action === 'send_transcript') {
    toggleEmailModal();
  } else if (action === 'export_txt') {
    exportTxt();
  } else if (action === 'print_pdf') {
    printPdf();
  }
};

// These functions are needed for the event listeners
const mute = () => {
  store.dispatch('muteConversation', currentChat.value.id);
  useAlert(t('CONTACT_PANEL.MUTED_SUCCESS'));
};

const unmute = () => {
  store.dispatch('unmuteConversation', currentChat.value.id);
  useAlert(t('CONTACT_PANEL.UNMUTED_SUCCESS'));
};

emitter.on(CMD_MUTE_CONVERSATION, mute);
emitter.on(CMD_UNMUTE_CONVERSATION, unmute);
emitter.on(CMD_SEND_TRANSCRIPT, toggleEmailModal);

onUnmounted(() => {
  emitter.off(CMD_MUTE_CONVERSATION, mute);
  emitter.off(CMD_UNMUTE_CONVERSATION, unmute);
  emitter.off(CMD_SEND_TRANSCRIPT, toggleEmailModal);
});
</script>

<template>
  <div class="relative flex items-center gap-2 actions--container">
    <ResolveAction
      :conversation-id="currentChat.id"
      :status="currentChat.status"
    />
    <div
      v-on-clickaway="() => toggleDropdown(false)"
      class="relative flex items-center group"
    >
      <ButtonV4
        v-tooltip="$t('CONVERSATION.HEADER.MORE_ACTIONS')"
        size="sm"
        variant="ghost"
        color="slate"
        icon="i-lucide-more-vertical"
        class="rounded-md group-hover:bg-n-alpha-2"
        @click="toggleDropdown()"
      />
      <DropdownMenu
        v-if="showActionsDropdown"
        :menu-items="actionMenuItems"
        class="mt-1 ltr:right-0 rtl:left-0 top-full"
        @action="handleActionClick"
      />
    </div>
    <EmailTranscriptModal
      v-if="showEmailActionsModal"
      :show="showEmailActionsModal"
      :current-chat="currentChat"
      @cancel="toggleEmailModal"
    />
  </div>
</template>
