<script>
import { mapActions, mapGetters } from 'vuex';
import { getContrastingTextColor } from '@chatwoot/utils';
import CustomButton from 'shared/components/Button.vue';
import FooterReplyTo from 'widget/components/FooterReplyTo.vue';
import ChatInputWrap from 'widget/components/ChatInputWrap.vue';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { sendEmailTranscript } from 'widget/api/conversation';
import { useRouter } from 'vue-router';
import { IFrameHelper } from '../helpers/utils';
import { CHATWOOT_ON_START_CONVERSATION } from '../constants/sdkEvents';
import { emitter } from 'shared/helpers/mitt';

export default {
  components: {
    ChatInputWrap,
    CustomButton,
    FooterReplyTo,
  },
  setup() {
    const router = useRouter();
    return { router };
  },
  data() {
    return {
      inReplyTo: null,
      showHotQuestions: true,
    };
  },
  computed: {
    ...mapGetters({
      conversationAttributes: 'conversationAttributes/getConversationParams',
      widgetColor: 'appConfig/getWidgetColor',
      conversationSize: 'conversation/getConversationSize',
      currentUser: 'contacts/getCurrentUser',
      isWidgetStyleFlat: 'appConfig/isWidgetStyleFlat',
    }),
    isChinese() {
      const locale =
        window.chatwootWebChannel?.locale || navigator.language || '';
      return locale.toLowerCase().startsWith('zh');
    },
    hotQuestions() {
      const settingsQuestions = window.chatwootSettings?.hotQuestions;
      if (Array.isArray(settingsQuestions) && settingsQuestions.length > 0) {
        return settingsQuestions;
      }
      const channelQuestions = window.chatwootWebChannel?.hotQuestions;
      if (Array.isArray(channelQuestions) && channelQuestions.length > 0) {
        return channelQuestions;
      }
      return this.isChinese
        ? [
            '节点无法连接排查',
            '客户端配置订阅教程',
            '续费与流量到账查询',
            '转接人工客服',
          ]
        : [
            'Node Connection Troubleshoot',
            'Client Subscription Setup',
            'Renewal & Traffic Balance',
            'Talk to an Agent',
          ];
    },
    textColor() {
      return getContrastingTextColor(this.widgetColor);
    },
    hideReplyBox() {
      const { allowMessagesAfterResolved } = window.chatwootWebChannel;
      const { status } = this.conversationAttributes;
      return !allowMessagesAfterResolved && status === 'resolved';
    },
    showEmailTranscriptButton() {
      return this.hasEmail;
    },
    hasEmail() {
      return this.currentUser && this.currentUser.has_email;
    },
    hasReplyTo() {
      return (
        this.inReplyTo && (this.inReplyTo.content || this.inReplyTo.attachments)
      );
    },
  },
  mounted() {
    emitter.on(BUS_EVENTS.TOGGLE_REPLY_TO_MESSAGE, this.toggleReplyTo);
  },
  methods: {
    ...mapActions('conversation', ['sendMessage', 'sendAttachment']),
    ...mapActions('conversationAttributes', ['getAttributes']),
    async handleSendMessage(content) {
      await this.sendMessage({
        content,
        replyTo: this.inReplyTo ? this.inReplyTo.id : null,
      });
      // reset replyTo message after sending
      this.inReplyTo = null;
      // Update conversation attributes on new conversation
      if (this.conversationSize === 0) {
        this.getAttributes();
      }
    },
    async handleSendAttachment(attachment) {
      await this.sendAttachment({
        attachment,
        replyTo: this.inReplyTo ? this.inReplyTo.id : null,
      });
      this.inReplyTo = null;
    },
    startNewConversation() {
      this.router.replace({ name: 'prechat-form' });
      IFrameHelper.sendMessage({
        event: 'onEvent',
        eventIdentifier: CHATWOOT_ON_START_CONVERSATION,
        data: { hasConversation: true },
      });
    },
    toggleReplyTo(message) {
      this.inReplyTo = message;
    },
    async sendTranscript() {
      if (this.hasEmail) {
        try {
          await sendEmailTranscript();
          emitter.emit(BUS_EVENTS.SHOW_ALERT, {
            message: this.$t('EMAIL_TRANSCRIPT.SEND_EMAIL_SUCCESS'),
            type: 'success',
          });
        } catch (error) {
          emitter.$emit(BUS_EVENTS.SHOW_ALERT, {
            message: this.$t('EMAIL_TRANSCRIPT.SEND_EMAIL_ERROR'),
          });
        }
      }
    },
  },
};
</script>

<template>
  <footer
    v-if="!hideReplyBox"
    class="relative z-50 mb-1"
    :style="{ paddingBottom: 'max(env(safe-area-inset-bottom, 0px), 4px)' }"
    :class="{
      'rounded-lg': !isWidgetStyleFlat,
      'pt-2.5 shadow-[0px_-20px_20px_1px_rgba(0,_0,_0,_0.05)] dark:shadow-[0px_-20px_20px_1px_rgba(0,_0,_0,_0.15)] rounded-t-none':
        hasReplyTo,
    }"
  >
    <FooterReplyTo
      v-if="hasReplyTo"
      :in-reply-to="inReplyTo"
      @dismiss="inReplyTo = null"
    />
    <div
      v-if="hotQuestions.length && showHotQuestions"
      class="flex items-center gap-1.5 px-3 py-1.5 bg-slate-50 dark:bg-slate-900/60 border-t border-slate-200/60 dark:border-slate-800"
    >
      <span
        class="text-[11px] font-medium text-slate-400 dark:text-slate-500 flex items-center gap-1 whitespace-nowrap flex-shrink-0"
      >
        <span class="i-lucide-sparkles size-3 text-amber-500" />
        {{ isChinese ? '猜你想问:' : 'Quick Questions:' }}
      </span>
      <div
        class="flex items-center gap-1.5 overflow-x-auto flex-1 py-0.5 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden"
      >
        <button
          v-for="(q, idx) in hotQuestions"
          :key="idx"
          type="button"
          class="whitespace-nowrap px-2.5 py-1 text-xs rounded-full bg-white dark:bg-slate-800 hover:bg-slate-100 dark:hover:bg-slate-700 text-slate-700 dark:text-slate-200 border border-slate-200 dark:border-slate-700 shadow-2xs transition-all active:scale-95 flex-shrink-0 cursor-pointer"
          @click="handleSendMessage(q)"
        >
          {{ q }}
        </button>
      </div>
      <button
        type="button"
        class="text-slate-400 hover:text-slate-600 dark:hover:text-slate-200 p-0.5 ml-1 flex-shrink-0 cursor-pointer"
        :title="isChinese ? '收起' : 'Dismiss'"
        @click="showHotQuestions = false"
      >
        <span class="i-lucide-x size-3.5" />
      </button>
    </div>
    <ChatInputWrap
      class="shadow-sm"
      :on-send-message="handleSendMessage"
      :on-send-attachment="handleSendAttachment"
    />
  </footer>
  <div v-else>
    <CustomButton
      class="font-medium"
      block
      :bg-color="widgetColor"
      :text-color="textColor"
      @click="startNewConversation"
    >
      {{ $t('START_NEW_CONVERSATION') }}
    </CustomButton>
    <CustomButton
      v-if="showEmailTranscriptButton"
      type="clear"
      class="font-normal"
      @click="sendTranscript"
    >
      {{ $t('EMAIL_TRANSCRIPT.BUTTON_TEXT') }}
    </CustomButton>
  </div>
</template>
