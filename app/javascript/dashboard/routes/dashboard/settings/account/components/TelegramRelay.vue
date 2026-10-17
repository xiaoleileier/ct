<script setup>
import { ref, watch, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import axios from 'axios';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import SectionLayout from './SectionLayout.vue';
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
  account => {
    if (account && account.id) {
      const s = account.settings || {};
      botToken.value = s.telegram_relay_bot_token || '';
      groupId.value = s.telegram_relay_group_id || '';
      isEnabled.value = s.telegram_relay_enabled ?? false;

      if (botToken.value && !statusResult.value && !isTesting.value) {
        handleTestConnection(true);
      }
    }
  },
  { deep: true, immediate: true }
);

onMounted(() => {
  if (botToken.value && !statusResult.value) {
    handleTestConnection(true);
  }
});

const botUsername = computed(() => statusResult.value?.bot?.username || '');
const botFirstName = computed(() => statusResult.value?.bot?.first_name || '');
const webhookUrl = computed(() => statusResult.value?.webhook?.url || '');
const webhookError = computed(
  () => statusResult.value?.webhook?.last_error_message || ''
);
const groupInfo = computed(() => statusResult.value?.group || null);
const isGroupBotReady = computed(() => {
  const g = statusResult.value?.group;
  return !!(g && g.bot_is_admin && g.can_manage_topics);
});

const handleSave = async () => {
  try {
    isSubmitting.value = true;
    await updateAccount({
      telegram_relay_bot_token: (botToken.value || '').trim(),
      telegram_relay_group_id: (groupId.value || '').trim(),
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
  const token = (botToken.value || '').trim();
  if (!token) {
    useAlert(t('GENERAL_SETTINGS.FORM.TELEGRAM_RELAY.API.WEBHOOK_ERROR'));
    return;
  }
  try {
    isSettingUpWebhook.value = true;
    // Always persist configuration first
    await updateAccount({
      telegram_relay_bot_token: token,
      telegram_relay_group_id: (groupId.value || '').trim(),
      telegram_relay_enabled: isEnabled.value,
    });

    const axiosClient = window.axios || axios;
    const response = await axiosClient.post('/webhooks/telegram_relay/setup', {
      account_id: accountId.value,
      bot_token: token,
    });

    if (response.data?.ok) {
      useAlert(t('GENERAL_SETTINGS.FORM.TELEGRAM_RELAY.API.WEBHOOK_SUCCESS'));
      await handleTestConnection(true);
    } else {
      useAlert(
        response.data?.telegram_response?.description ||
          response.data?.error ||
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
  const token = (botToken.value || '').trim();
  if (!token) {
    if (!silent) {
      useAlert(t('GENERAL_SETTINGS.FORM.TELEGRAM_RELAY.API.WEBHOOK_ERROR'));
    }
    return;
  }
  try {
    isTesting.value = true;
    const axiosClient = window.axios || axios;
    const response = await axiosClient.get('/webhooks/telegram_relay/status', {
      params: {
        account_id: accountId.value,
        bot_token: token,
        group_id: (groupId.value || '').trim(),
      },
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
      <!-- Configuration Guide Box -->
      <div
        class="p-4 rounded-xl bg-n-alpha-1 dark:bg-n-solid-2 border border-n-weak text-xs text-n-slate-11 leading-relaxed"
      >
        <div
          class="font-medium text-n-slate-12 mb-2 flex items-center gap-1.5 text-sm"
        >
          <span>💡</span>
          <span>配置说明指南</span>
        </div>
        <ol class="list-decimal list-inside space-y-1.5">
          <li>
            <b>创建机器人并获取 Token</b>：在 Telegram 中与
            <a
              href="https://t.me/BotFather"
              target="_blank"
              rel="noopener noreferrer"
              class="text-n-blue-11 underline font-medium"
            >
              @BotFather
            </a>
            对话，发送 <code>/newbot</code> 按照提示创建机器人，复制生成的 HTTP API Token，填入下方的「Bot Token」。
          </li>
          <li>
            <b>开启群组 Topics 话题功能</b>：在 Telegram 创建或选择一个超级群组，点击群组右上角设置 ➔ 开启
            <b>Topics（话题）</b> 功能。
          </li>
          <li>
            <b>机器人进群并设为管理员</b>：将该机器人拉入超级群组中，在管理员设置中将其添加为管理员，并确保勾选
            <b>Manage Topics（管理话题）</b> 权限。
          </li>
          <li>
            <b>填写群组 ID 并激活</b>：将群组 ID（超级群组 ID 必须以 <code>-100</code> 开头）填入下方「群组 ID」，点击「保存 Telegram 配置」，再点击「一键激活 Webhook」。
          </li>
          <li>
            <b>实用技巧</b>：在 TG 话题内发送 <code>/close</code> 或直接在 TG 关闭话题，系统会自动标记会话已解决；在后台重新打开会话，TG 话题也会自动重新打开。
          </li>
        </ol>
      </div>

      <!-- Telegram Settings Form -->
      <form class="grid gap-4" @submit.prevent="handleSave">
        <!-- Bot Token Input -->
        <div class="space-y-1.5">
          <label
            class="flex items-center justify-between text-sm font-medium text-n-slate-12"
          >
            <span class="flex items-center gap-1.5">
              <span>🤖</span>
              <span>{{
                t('GENERAL_SETTINGS.FORM.TELEGRAM_RELAY.BOT_TOKEN.LABEL')
              }}</span>
            </span>
            <span class="text-xs text-n-slate-10">从 @BotFather 获取</span>
          </label>
          <NextInput
            v-model="botToken"
            type="text"
            class="w-full font-mono text-sm"
            :placeholder="
              t('GENERAL_SETTINGS.FORM.TELEGRAM_RELAY.BOT_TOKEN.PLACEHOLDER')
            "
          />
          <p class="text-xs text-n-slate-10 leading-normal">
            {{ t('GENERAL_SETTINGS.FORM.TELEGRAM_RELAY.BOT_TOKEN.HELP') }}
          </p>
        </div>

        <!-- Group ID Input -->
        <div class="space-y-1.5">
          <label
            class="flex items-center justify-between text-sm font-medium text-n-slate-12"
          >
            <span class="flex items-center gap-1.5">
              <span>👥</span>
              <span>{{
                t('GENERAL_SETTINGS.FORM.TELEGRAM_RELAY.GROUP_ID.LABEL')
              }}</span>
            </span>
            <span class="text-xs text-n-slate-10">以 -100 开头</span>
          </label>
          <NextInput
            v-model="groupId"
            type="text"
            class="w-full font-mono text-sm"
            :placeholder="
              t('GENERAL_SETTINGS.FORM.TELEGRAM_RELAY.GROUP_ID.PLACEHOLDER')
            "
          />
          <p class="text-xs text-n-slate-10 leading-normal">
            {{ t('GENERAL_SETTINGS.FORM.TELEGRAM_RELAY.GROUP_ID.HELP') }}
          </p>
        </div>

        <!-- Status & Diagnostic Details -->
        <div
          v-if="statusResult"
          class="p-4 rounded-xl border text-xs space-y-2.5 transition-all"
          :class="
            statusResult.ok
              ? 'bg-n-alpha-1 dark:bg-n-solid-2 border-n-teal-6 text-n-slate-12'
              : 'bg-n-ruby-2/30 border-n-ruby-6 text-n-ruby-12'
          "
        >
          <div v-if="statusResult.ok" class="space-y-2">
            <div
              class="font-medium text-sm text-n-teal-11 flex items-center gap-1.5 pb-1 border-b border-n-weak"
            >
              <span>🩺</span>
              <span>Telegram 机器人体检报告 (Diagnostic Report)</span>
            </div>

            <!-- Bot Status -->
            <div class="flex items-center gap-2">
              <span class="text-n-teal-11">✅</span>
              <span>
                机器人账号：
                <b class="text-n-slate-12">@{{ botUsername }}</b>
                <span class="text-n-slate-10 text-[11px] ml-1">
                  ({{ botFirstName }})
                </span>
              </span>
            </div>

            <!-- Webhook Status -->
            <div class="flex items-start gap-2">
              <span :class="webhookUrl ? 'text-n-teal-11' : 'text-n-ruby-11'">
                {{ webhookUrl ? '✅' : '⚠️' }}
              </span>
              <div class="flex-1">
                <span>Webhook 回调地址：</span>
                <code
                  v-if="webhookUrl"
                  class="text-xs break-all text-n-blue-11 block mt-0.5"
                >
                  {{ webhookUrl }}
                </code>
                <span v-else class="text-n-ruby-11 font-medium block mt-0.5">
                  未注册！请点击下方的「一键激活 Webhook」按钮进行激活。
                </span>
                <div
                  v-if="webhookError"
                  class="text-n-ruby-11 mt-1 font-medium"
                >
                  ⚠️ 异常提示: {{ webhookError }}
                </div>
              </div>
            </div>

            <!-- Group Status -->
            <div
              v-if="groupInfo"
              class="pt-1 space-y-1.5 border-t border-n-weak"
            >
              <div v-if="groupInfo.valid" class="space-y-1.5">
                <div class="flex items-center gap-2">
                  <span class="text-n-teal-11">✅</span>
                  <span>
                    已连接群组：<b class="text-n-slate-12">「{{ groupInfo.title }}」</b>
                  </span>
                </div>

                <div class="flex items-center gap-2">
                  <span
                    :class="
                      groupInfo.is_forum ? 'text-n-teal-11' : 'text-n-ruby-11'
                    "
                  >
                    {{ groupInfo.is_forum ? '✅' : '❌' }}
                  </span>
                  <span v-if="groupInfo.is_forum" class="text-n-slate-12">
                    Topics 话题功能已开启 (Forum Supergroup)
                  </span>
                  <span v-else class="text-n-ruby-11 font-medium">
                    群组尚未开启话题！请点击群设置 ➔ 开启「Topics 话题功能」。
                  </span>
                </div>

                <div class="flex items-center gap-2">
                  <span
                    :class="
                      isGroupBotReady ? 'text-n-teal-11' : 'text-n-ruby-11'
                    "
                  >
                    {{ isGroupBotReady ? '✅' : '❌' }}
                  </span>
                  <span v-if="isGroupBotReady" class="text-n-slate-12">
                    机器人管理员权限已就绪 (包含 Manage Topics 话题管理权限)
                  </span>
                  <span v-else class="text-n-ruby-11 font-medium">
                    机器人权限不足！请在群管理中将机器人设为管理员并勾选「Manage Topics」。
                  </span>
                </div>
              </div>

              <div v-else class="flex items-center gap-2 text-n-ruby-11">
                <span>❌</span>
                <span>
                  无法访问群组 ({{ groupInfo.error }})。请确保已将机器人拉入群组，且群组 ID 填写正确（以 -100 开头）。
                </span>
              </div>
            </div>
          </div>

          <div v-else class="flex items-center gap-2">
            <span>❌</span>
            <span class="font-medium">
              {{ statusResult.error || '连接失败，请检查 Bot Token 是否正确' }}
            </span>
          </div>
        </div>

        <!-- Action Buttons -->
        <div class="flex flex-wrap items-center gap-3 pt-2">
          <NextButton
            blue
            :is-loading="isSubmitting"
            type="submit"
          >
            {{ t('GENERAL_SETTINGS.FORM.TELEGRAM_RELAY.UPDATE_BUTTON') }}
          </NextButton>
          <NextButton
            variant="outline"
            color="slate"
            :is-loading="isSettingUpWebhook"
            type="button"
            @click="handleSetupWebhook"
          >
            {{ t('GENERAL_SETTINGS.FORM.TELEGRAM_RELAY.SETUP_WEBHOOK') }}
          </NextButton>
          <NextButton
            ghost
            color="slate"
            :is-loading="isTesting"
            type="button"
            @click="() => handleTestConnection(false)"
          >
            {{ t('GENERAL_SETTINGS.FORM.TELEGRAM_RELAY.TEST_CONNECTION') }}
          </NextButton>
        </div>
      </form>
    </div>
  </SectionLayout>
</template>
