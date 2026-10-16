<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import axios from 'axios';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import SectionLayout from './SectionLayout.vue';
import WithLabel from 'v3/components/Form/WithLabel.vue';
import NextInput from 'next/input/Input.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Switch from 'next/switch/Switch.vue';

const { t } = useI18n();
const { accountId, currentAccount, updateAccount } = useAccount();

const isEnabled = ref(false);
const botToken = ref('');
const groupId = ref('');
const isSubmitting = ref(false);
const isSettingUpWebhook = ref(false);
const isTesting = ref(false);
const statusResult = ref(null);

watch(
  currentAccount,
  () => {
    const settings = currentAccount.value?.settings || {};
    botToken.value = settings.telegram_relay_bot_token || '';
    groupId.value = settings.telegram_relay_group_id || '';
    isEnabled.value = settings.telegram_relay_enabled ?? false;
  },
  { deep: true, immediate: true }
);

const handleSave = async () => {
  try {
    isSubmitting.value = true;
    await updateAccount({
      telegram_relay_bot_token: botToken.value.trim(),
      telegram_relay_group_id: groupId.value.trim(),
      telegram_relay_enabled: isEnabled.value,
    });
    useAlert(t('GENERAL_SETTINGS.FORM.TELEGRAM_RELAY.API.SUCCESS'));
  } catch (error) {
    useAlert(t('GENERAL_SETTINGS.FORM.TELEGRAM_RELAY.API.ERROR'));
  } finally {
    isSubmitting.value = false;
  }
};

const handleToggle = async () => {
  return handleSave();
};

const handleSetupWebhook = async () => {
  if (!botToken.value) {
    useAlert(t('GENERAL_SETTINGS.FORM.TELEGRAM_RELAY.API.WEBHOOK_ERROR'));
    return;
  }
  try {
    isSettingUpWebhook.value = true;
    // Save first to ensure the backend has the latest token
    await updateAccount({
      telegram_relay_bot_token: botToken.value.trim(),
      telegram_relay_group_id: groupId.value.trim(),
      telegram_relay_enabled: isEnabled.value,
    });

    const response = await axios.post('/webhooks/telegram_relay/setup', {
      account_id: accountId.value,
    });

    if (response.data?.ok) {
      useAlert(t('GENERAL_SETTINGS.FORM.TELEGRAM_RELAY.API.WEBHOOK_SUCCESS'));
      await handleTestConnection(true);
    } else {
      useAlert(
        response.data?.telegram_response?.description ||
          t('GENERAL_SETTINGS.FORM.TELEGRAM_RELAY.API.WEBHOOK_ERROR')
      );
    }
  } catch (error) {
    useAlert(
      error.response?.data?.error ||
        t('GENERAL_SETTINGS.FORM.TELEGRAM_RELAY.API.WEBHOOK_ERROR')
    );
  } finally {
    isSettingUpWebhook.value = false;
  }
};

const handleTestConnection = async (silent = false) => {
  try {
    isTesting.value = true;
    const response = await axios.get('/webhooks/telegram_relay/status', {
      params: { account_id: accountId.value },
    });
    statusResult.value = response.data;
    if (!silent) {
      if (response.data?.ok) {
        useAlert(
          t('GENERAL_SETTINGS.FORM.TELEGRAM_RELAY.STATUS_CONNECTED', {
            botName: response.data?.bot?.username || 'Bot',
          })
        );
      } else {
        useAlert(
          response.data?.error ||
            t('GENERAL_SETTINGS.FORM.TELEGRAM_RELAY.STATUS_ERROR')
        );
      }
    }
  } catch (error) {
    statusResult.value = {
      ok: false,
      error: error.response?.data?.error || error.message,
    };
    if (!silent) {
      useAlert(
        error.response?.data?.error ||
          t('GENERAL_SETTINGS.FORM.TELEGRAM_RELAY.STATUS_ERROR')
      );
    }
  } finally {
    isTesting.value = false;
  }
};
</script>

<template>
  <SectionLayout
    :title="t('GENERAL_SETTINGS.FORM.TELEGRAM_RELAY.TITLE')"
    :description="t('GENERAL_SETTINGS.FORM.TELEGRAM_RELAY.NOTE')"
    with-border
  >
    <template #headerActions>
      <div class="flex justify-end">
        <Switch v-model="isEnabled" @change="handleToggle" />
      </div>
    </template>

    <div class="flex flex-col gap-4">
      <!-- Setup Instructions Card -->
      <div
        class="p-4 rounded-xl bg-n-alpha-1 dark:bg-n-solid-2 border border-n-weak text-xs text-n-slate-11 leading-relaxed"
      >
        <div class="font-medium text-n-slate-12 mb-1.5 flex items-center gap-1.5">
          <span>💡</span>
          <span>配置指南 (How to setup):</span>
        </div>
        <ol class="list-decimal list-inside space-y-1">
          <li>
            在 Telegram 中搜索
            <a
              href="https://t.me/BotFather"
              target="_blank"
              rel="noopener noreferrer"
              class="text-n-blue-11 underline"
            >
              @BotFather
            </a>
            ，发送 <code>/newbot</code> 创建机器人并复制获得的 Token。
          </li>
          <li>
            在 Telegram 创建或选择一个超级群组，在群设置中开启
            <span class="font-semibold text-n-slate-12">Topics (话题功能)</span>。
          </li>
          <li>
            将机器人拉入群组，并设置为群管理员（确保勾选
            <span class="font-semibold text-n-slate-12">Manage Topics</span> 权限）。
          </li>
          <li>
            将群组 ID（以 <code>-100</code> 开头）与 Bot Token 填入下方，点击「保存 Telegram 配置」，再点击「一键激活 Webhook」。
          </li>
        </ol>
      </div>

      <!-- Settings Form -->
      <form class="grid gap-4" @submit.prevent="handleSave">
        <WithLabel
          :label="t('GENERAL_SETTINGS.FORM.TELEGRAM_RELAY.BOT_TOKEN.LABEL')"
        >
          <NextInput
            v-model="botToken"
            type="password"
            class="w-full font-mono text-sm"
            :placeholder="
              t('GENERAL_SETTINGS.FORM.TELEGRAM_RELAY.BOT_TOKEN.PLACEHOLDER')
            "
          />
          <template #help>
            {{ t('GENERAL_SETTINGS.FORM.TELEGRAM_RELAY.BOT_TOKEN.HELP') }}
          </template>
        </WithLabel>

        <WithLabel
          :label="t('GENERAL_SETTINGS.FORM.TELEGRAM_RELAY.GROUP_ID.LABEL')"
        >
          <NextInput
            v-model="groupId"
            type="text"
            class="w-full font-mono text-sm"
            :placeholder="
              t('GENERAL_SETTINGS.FORM.TELEGRAM_RELAY.GROUP_ID.PLACEHOLDER')
            "
          />
          <template #help>
            {{ t('GENERAL_SETTINGS.FORM.TELEGRAM_RELAY.GROUP_ID.HELP') }}
          </template>
        </WithLabel>

        <!-- Status Details if Checked -->
        <div
          v-if="statusResult"
          class="p-3 rounded-lg border text-xs"
          :class="
            statusResult.ok
              ? 'bg-n-teal-2/30 border-n-teal-6 text-n-teal-12'
              : 'bg-n-ruby-2/30 border-n-ruby-6 text-n-ruby-12'
          "
        >
          <div v-if="statusResult.ok" class="space-y-1">
            <div class="font-medium flex items-center gap-1.5">
              <span>✅</span>
              <span>
                {{
                  t('GENERAL_SETTINGS.FORM.TELEGRAM_RELAY.STATUS_CONNECTED', {
                    botName: statusResult.bot?.username || statusResult.bot?.first_name,
                  })
                }}
              </span>
            </div>
            <div class="text-n-slate-11">
              <span>Webhook: </span>
              <code class="text-xs break-all">{{
                statusResult.webhook?.url || '未注册'
              }}</code>
            </div>
            <div
              v-if="statusResult.webhook?.last_error_message"
              class="text-n-ruby-11 mt-1"
            >
              ⚠️ Telegram 报告错误: {{ statusResult.webhook.last_error_message }}
            </div>
          </div>
          <div v-else class="flex items-center gap-1.5">
            <span>❌</span>
            <span>{{ statusResult.error || '连接失败' }}</span>
          </div>
        </div>

        <div class="flex flex-wrap items-center gap-3 pt-2">
          <NextButton
            blue
            :is-loading="isSubmitting"
            type="submit"
            :label="t('GENERAL_SETTINGS.FORM.TELEGRAM_RELAY.UPDATE_BUTTON')"
          />
          <NextButton
            variant="outline"
            :is-loading="isSettingUpWebhook"
            type="button"
            :label="t('GENERAL_SETTINGS.FORM.TELEGRAM_RELAY.SETUP_WEBHOOK')"
            @click="handleSetupWebhook"
          />
          <NextButton
            ghost
            :is-loading="isTesting"
            type="button"
            :label="t('GENERAL_SETTINGS.FORM.TELEGRAM_RELAY.TEST_CONNECTION')"
            @click="() => handleTestConnection(false)"
          />
        </div>
      </form>
    </div>
  </SectionLayout>
</template>
