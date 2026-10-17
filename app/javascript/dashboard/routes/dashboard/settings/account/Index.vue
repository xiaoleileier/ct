<script>
import { useVuelidate } from '@vuelidate/core';
import { required } from '@vuelidate/validators';
import { mapGetters } from 'vuex';
import axios from 'axios';
import { useAlert } from 'dashboard/composables';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useConfig } from 'dashboard/composables/useConfig';
import { useAccount } from 'dashboard/composables/useAccount';
import { FEATURE_FLAGS } from '../../../../featureFlags';
import WithLabel from 'v3/components/Form/WithLabel.vue';
import NextInput from 'next/input/Input.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import AccountId from './components/AccountId.vue';
import BuildInfo from './components/BuildInfo.vue';
import AccountDelete from './components/AccountDelete.vue';
import AutoResolve from './components/AutoResolve.vue';
import AudioTranscription from './components/AudioTranscription.vue';
import SectionLayout from './components/SectionLayout.vue';
import Switch from 'next/switch/Switch.vue';

export default {
  components: {
    BaseSettingsHeader,
    NextButton,
    AccountId,
    BuildInfo,
    AccountDelete,
    AutoResolve,
    AudioTranscription,
    SectionLayout,
    WithLabel,
    NextInput,
    Switch,
  },
  setup() {
    const { updateUISettings, uiSettings } = useUISettings();
    const { enabledLanguages } = useConfig();
    const { accountId } = useAccount();
    const v$ = useVuelidate();

    return { updateUISettings, uiSettings, v$, enabledLanguages, accountId };
  },
  data() {
    return {
      id: '',
      name: '',
      locale: 'en',
      domain: '',
      supportEmail: '',
      features: {},
      telegramRelayEnabled: false,
      telegramRelayBotToken: '',
      telegramRelayGroupId: '',
      isSavingTelegramRelay: false,
      isSettingUpTelegramWebhook: false,
      isTestingTelegramConnection: false,
      telegramRelayStatus: null,
    };
  },
  validations: {
    name: {
      required,
    },
    locale: {
      required,
    },
  },
  computed: {
    ...mapGetters({
      getAccount: 'accounts/getAccount',
      uiFlags: 'accounts/getUIFlags',
      isFeatureEnabledonAccount: 'accounts/isFeatureEnabledonAccount',
      isOnChatwootCloud: 'globalConfig/isOnChatwootCloud',
    }),
    showAutoResolutionConfig() {
      return this.isFeatureEnabledonAccount(
        this.accountId,
        FEATURE_FLAGS.AUTO_RESOLVE_CONVERSATIONS
      );
    },
    showAudioTranscriptionConfig() {
      return this.isFeatureEnabledonAccount(
        this.accountId,
        FEATURE_FLAGS.CAPTAIN
      );
    },
    languagesSortedByCode() {
      const enabledLanguages = [...this.enabledLanguages];
      return enabledLanguages.sort((l1, l2) =>
        l1.iso_639_1_code.localeCompare(l2.iso_639_1_code)
      );
    },
    isUpdating() {
      return this.uiFlags.isUpdating;
    },
    featureInboundEmailEnabled() {
      return !!this.features?.inbound_emails;
    },
    featureCustomReplyDomainEnabled() {
      return (
        this.featureInboundEmailEnabled && !!this.features.custom_reply_domain
      );
    },
    featureCustomReplyEmailEnabled() {
      return (
        this.featureInboundEmailEnabled && !!this.features.custom_reply_email
      );
    },
    currentAccount() {
      return this.getAccount(this.accountId) || {};
    },
    telegramRelayBotUsername() {
      return this.telegramRelayStatus?.bot?.username || '';
    },
    telegramRelayBotFirstName() {
      return this.telegramRelayStatus?.bot?.first_name || '';
    },
    telegramRelayWebhookUrl() {
      return this.telegramRelayStatus?.webhook?.url || '';
    },
    telegramRelayWebhookError() {
      return this.telegramRelayStatus?.webhook?.last_error_message || '';
    },
    telegramRelayGroupInfo() {
      return this.telegramRelayStatus?.group || null;
    },
    telegramRelayGroupBotReady() {
      const g = this.telegramRelayStatus?.group;
      return !!(g && g.bot_is_admin && g.can_manage_topics);
    },
  },
  watch: {
    currentAccount: {
      handler(account) {
        if (account && account.id) {
          const s = account.settings || {};
          this.telegramRelayBotToken = s.telegram_relay_bot_token || '';
          this.telegramRelayGroupId = s.telegram_relay_group_id || '';
          this.telegramRelayEnabled = s.telegram_relay_enabled ?? false;
        }
      },
      deep: true,
      immediate: true,
    },
  },
  mounted() {
    this.initializeAccount();
  },
  methods: {
    async initializeAccount() {
      try {
        const {
          name,
          locale,
          id,
          domain,
          support_email,
          features,
          settings,
        } = this.getAccount(this.accountId) || {};

        this.$root.$i18n.locale = this.uiSettings?.locale || locale;
        this.name = name;
        this.locale = locale;
        this.id = id;
        this.domain = domain;
        this.supportEmail = support_email;
        this.features = features;

        const s = settings || {};
        this.telegramRelayBotToken = s.telegram_relay_bot_token || '';
        this.telegramRelayGroupId = s.telegram_relay_group_id || '';
        this.telegramRelayEnabled = s.telegram_relay_enabled ?? false;
      } catch (error) {
        // Ignore error
      }
    },

    async updateAccount() {
      this.v$.$touch();
      if (this.v$.$invalid) {
        useAlert(this.$t('GENERAL_SETTINGS.FORM.ERROR'));
        return;
      }
      try {
        await this.$store.dispatch('accounts/update', {
          locale: this.locale,
          name: this.name,
          domain: this.domain,
          support_email: this.supportEmail,
        });
        // If user locale is set, update the locale with user locale
        if (this.uiSettings?.locale) {
          this.$root.$i18n.locale = this.uiSettings?.locale;
        } else {
          // If user locale is not set, update the locale with account locale
          this.$root.$i18n.locale = this.locale;
        }
        this.getAccount(this.id).locale = this.locale;
        useAlert(this.$t('GENERAL_SETTINGS.UPDATE.SUCCESS'));
      } catch (error) {
        useAlert(this.$t('GENERAL_SETTINGS.UPDATE.ERROR'));
      }
    },

    async saveTelegramRelay() {
      try {
        this.isSavingTelegramRelay = true;
        await this.$store.dispatch('accounts/update', {
          telegram_relay_bot_token: (this.telegramRelayBotToken || '').trim(),
          telegram_relay_group_id: (this.telegramRelayGroupId || '').trim(),
          telegram_relay_enabled: this.telegramRelayEnabled,
        });
        useAlert(this.$t('GENERAL_SETTINGS.FORM.TELEGRAM_RELAY.API.SUCCESS'));
      } catch (error) {
        useAlert(this.$t('GENERAL_SETTINGS.FORM.TELEGRAM_RELAY.API.ERROR'));
      } finally {
        this.isSavingTelegramRelay = false;
      }
    },

    async handleToggleTelegramRelay() {
      return this.saveTelegramRelay();
    },

    async setupTelegramWebhook() {
      if (!this.telegramRelayBotToken) {
        useAlert(
          this.$t('GENERAL_SETTINGS.FORM.TELEGRAM_RELAY.API.WEBHOOK_ERROR')
        );
        return;
      }
      try {
        this.isSettingUpTelegramWebhook = true;
        await this.$store.dispatch('accounts/update', {
          telegram_relay_bot_token: (this.telegramRelayBotToken || '').trim(),
          telegram_relay_group_id: (this.telegramRelayGroupId || '').trim(),
          telegram_relay_enabled: this.telegramRelayEnabled,
        });

        const axiosClient = window.axios || axios;
        const response = await axiosClient.post(
          '/webhooks/telegram_relay/setup',
          {
            account_id: this.accountId,
          }
        );

        if (response.data && response.data.ok) {
          useAlert(
            this.$t('GENERAL_SETTINGS.FORM.TELEGRAM_RELAY.API.WEBHOOK_SUCCESS')
          );
          await this.testTelegramConnection(true);
        } else {
          const desc = response.data?.telegram_response?.description;
          useAlert(
            desc ||
              this.$t('GENERAL_SETTINGS.FORM.TELEGRAM_RELAY.API.WEBHOOK_ERROR')
          );
        }
      } catch (error) {
        useAlert(
          error.response?.data?.error ||
            this.$t('GENERAL_SETTINGS.FORM.TELEGRAM_RELAY.API.WEBHOOK_ERROR')
        );
      } finally {
        this.isSettingUpTelegramWebhook = false;
      }
    },

    async testTelegramConnection(silent = false) {
      try {
        this.isTestingTelegramConnection = true;
        const axiosClient = window.axios || axios;
        const response = await axiosClient.get(
          '/webhooks/telegram_relay/status',
          {
            params: { account_id: this.accountId },
          }
        );
        this.telegramRelayStatus = response.data;
        if (!silent) {
          if (response.data && response.data.ok) {
            useAlert(
              this.$t('GENERAL_SETTINGS.FORM.TELEGRAM_RELAY.STATUS_CONNECTED', {
                botName: response.data.bot?.username || 'Bot',
              })
            );
          } else {
            useAlert(
              response.data?.error ||
                this.$t('GENERAL_SETTINGS.FORM.TELEGRAM_RELAY.STATUS_ERROR')
            );
          }
        }
      } catch (error) {
        this.telegramRelayStatus = {
          ok: false,
          error: error.response?.data?.error || error.message,
        };
        if (!silent) {
          useAlert(
            error.response?.data?.error ||
              this.$t('GENERAL_SETTINGS.FORM.TELEGRAM_RELAY.STATUS_ERROR')
          );
        }
      } finally {
        this.isTestingTelegramConnection = false;
      }
    },
  },
};
</script>

<template>
  <div class="flex flex-col max-w-2xl mx-auto w-full">
    <BaseSettingsHeader :title="$t('GENERAL_SETTINGS.TITLE')" />
    <div class="flex-grow flex-shrink min-w-0 mt-3">
      <SectionLayout
        :title="$t('GENERAL_SETTINGS.FORM.GENERAL_SECTION.TITLE')"
        :description="$t('GENERAL_SETTINGS.FORM.GENERAL_SECTION.NOTE')"
      >
        <form
          v-if="!uiFlags.isFetchingItem"
          class="grid gap-4"
          @submit.prevent="updateAccount"
        >
          <WithLabel
            :has-error="v$.name.$error"
            :label="$t('GENERAL_SETTINGS.FORM.NAME.LABEL')"
            :error-message="$t('GENERAL_SETTINGS.FORM.NAME.ERROR')"
          >
            <NextInput
              v-model="name"
              type="text"
              class="w-full"
              :placeholder="$t('GENERAL_SETTINGS.FORM.NAME.PLACEHOLDER')"
              @blur="v$.name.$touch"
            />
          </WithLabel>
          <WithLabel
            :has-error="v$.locale.$error"
            :label="$t('GENERAL_SETTINGS.FORM.LANGUAGE.LABEL')"
            :error-message="$t('GENERAL_SETTINGS.FORM.LANGUAGE.ERROR')"
          >
            <select v-model="locale" class="!mb-0 text-sm">
              <option
                v-for="lang in languagesSortedByCode"
                :key="lang.iso_639_1_code"
                :value="lang.iso_639_1_code"
              >
                {{ lang.name }}
              </option>
            </select>
          </WithLabel>
          <WithLabel
            v-if="featureCustomReplyDomainEnabled"
            :label="$t('GENERAL_SETTINGS.FORM.DOMAIN.LABEL')"
          >
            <NextInput
              v-model="domain"
              type="text"
              class="w-full"
              :placeholder="$t('GENERAL_SETTINGS.FORM.DOMAIN.PLACEHOLDER')"
            />
            <template #help>
              {{
                featureInboundEmailEnabled &&
                $t('GENERAL_SETTINGS.FORM.FEATURES.INBOUND_EMAIL_ENABLED')
              }}

              {{
                featureCustomReplyDomainEnabled &&
                $t('GENERAL_SETTINGS.FORM.FEATURES.CUSTOM_EMAIL_DOMAIN_ENABLED')
              }}
            </template>
          </WithLabel>
          <WithLabel
            v-if="featureCustomReplyEmailEnabled"
            :label="$t('GENERAL_SETTINGS.FORM.SUPPORT_EMAIL.LABEL')"
          >
            <NextInput
              v-model="supportEmail"
              type="text"
              class="w-full"
              :placeholder="
                $t('GENERAL_SETTINGS.FORM.SUPPORT_EMAIL.PLACEHOLDER')
              "
            />
          </WithLabel>
          <div>
            <NextButton blue :is-loading="isUpdating" type="submit">
              {{ $t('GENERAL_SETTINGS.SUBMIT') }}
            </NextButton>
          </div>
        </form>
      </SectionLayout>

      <woot-loading-state v-if="uiFlags.isFetchingItem" />
    </div>
    <AutoResolve v-if="showAutoResolutionConfig" />
    <AudioTranscription v-if="showAudioTranscriptionConfig" />
    <!-- Telegram Relay Bot Section -->
    <SectionLayout
      :title="$t('GENERAL_SETTINGS.FORM.TELEGRAM_RELAY.TITLE')"
      :description="$t('GENERAL_SETTINGS.FORM.TELEGRAM_RELAY.NOTE')"
      with-border
    >
      <template #headerActions>
        <div class="flex justify-end">
          <Switch
            v-model="telegramRelayEnabled"
            @change="handleToggleTelegramRelay"
          />
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
          </ol>
        </div>

        <!-- Telegram Settings Form -->
        <form class="grid gap-4" @submit.prevent="saveTelegramRelay">
          <WithLabel
            :label="$t('GENERAL_SETTINGS.FORM.TELEGRAM_RELAY.BOT_TOKEN.LABEL')"
            name="telegramRelayBotToken"
          >
            <NextInput
              v-model="telegramRelayBotToken"
              type="text"
              class="w-full font-mono text-sm"
              :placeholder="
                $t('GENERAL_SETTINGS.FORM.TELEGRAM_RELAY.BOT_TOKEN.PLACEHOLDER')
              "
            />
            <template #help>
              {{ $t('GENERAL_SETTINGS.FORM.TELEGRAM_RELAY.BOT_TOKEN.HELP') }}
            </template>
          </WithLabel>

          <WithLabel
            :label="$t('GENERAL_SETTINGS.FORM.TELEGRAM_RELAY.GROUP_ID.LABEL')"
            name="telegramRelayGroupId"
          >
            <NextInput
              v-model="telegramRelayGroupId"
              type="text"
              class="w-full font-mono text-sm"
              :placeholder="
                $t('GENERAL_SETTINGS.FORM.TELEGRAM_RELAY.GROUP_ID.PLACEHOLDER')
              "
            />
            <template #help>
              {{ $t('GENERAL_SETTINGS.FORM.TELEGRAM_RELAY.GROUP_ID.HELP') }}
            </template>
          </WithLabel>

          <!-- Status & Diagnostic Details -->
          <div
            v-if="telegramRelayStatus"
            class="p-4 rounded-xl border text-xs space-y-2.5 transition-all"
            :class="
              telegramRelayStatus.ok
                ? 'bg-n-alpha-1 dark:bg-n-solid-2 border-n-teal-6 text-n-slate-12'
                : 'bg-n-ruby-2/30 border-n-ruby-6 text-n-ruby-12'
            "
          >
            <div v-if="telegramRelayStatus.ok" class="space-y-2">
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
                  <b class="text-n-slate-12">@{{ telegramRelayBotUsername }}</b>
                  <span class="text-n-slate-10 text-[11px] ml-1">
                    ({{ telegramRelayBotFirstName }})
                  </span>
                </span>
              </div>

              <!-- Webhook Status -->
              <div class="flex items-start gap-2">
                <span
                  :class="
                    telegramRelayWebhookUrl ? 'text-n-teal-11' : 'text-n-ruby-11'
                  "
                >
                  {{ telegramRelayWebhookUrl ? '✅' : '⚠️' }}
                </span>
                <div class="flex-1">
                  <span>Webhook 回调地址：</span>
                  <code
                    v-if="telegramRelayWebhookUrl"
                    class="text-xs break-all text-n-blue-11 block mt-0.5"
                  >
                    {{ telegramRelayWebhookUrl }}
                  </code>
                  <span v-else class="text-n-ruby-11 font-medium block mt-0.5">
                    未注册！请点击下方的「一键激活 Webhook」按钮进行激活。
                  </span>
                  <div
                    v-if="telegramRelayWebhookError"
                    class="text-n-ruby-11 mt-1 font-medium"
                  >
                    ⚠️ 异常提示: {{ telegramRelayWebhookError }}
                  </div>
                </div>
              </div>

              <!-- Group Status -->
              <div
                v-if="telegramRelayGroupInfo"
                class="pt-1 space-y-1.5 border-t border-n-weak"
              >
                <div v-if="telegramRelayGroupInfo.valid" class="space-y-1.5">
                  <div class="flex items-center gap-2">
                    <span class="text-n-teal-11">✅</span>
                    <span>
                      已连接群组：<b class="text-n-slate-12">「{{ telegramRelayGroupInfo.title }}」</b>
                    </span>
                  </div>

                  <div class="flex items-center gap-2">
                    <span
                      :class="
                        telegramRelayGroupInfo.is_forum
                          ? 'text-n-teal-11'
                          : 'text-n-ruby-11'
                      "
                    >
                      {{ telegramRelayGroupInfo.is_forum ? '✅' : '❌' }}
                    </span>
                    <span
                      v-if="telegramRelayGroupInfo.is_forum"
                      class="text-n-slate-12"
                    >
                      Topics 话题功能已开启 (Forum Supergroup)
                    </span>
                    <span v-else class="text-n-ruby-11 font-medium">
                      群组尚未开启话题！请点击群设置 ➔ 开启「Topics 话题功能」。
                    </span>
                  </div>

                  <div class="flex items-center gap-2">
                    <span
                      :class="
                        telegramRelayGroupBotReady
                          ? 'text-n-teal-11'
                          : 'text-n-ruby-11'
                      "
                    >
                      {{ telegramRelayGroupBotReady ? '✅' : '❌' }}
                    </span>
                    <span
                      v-if="telegramRelayGroupBotReady"
                      class="text-n-slate-12"
                    >
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
                    无法访问群组 ({{ telegramRelayGroupInfo.error }})。请确保已将机器人拉入群组，且群组 ID 填写正确（以 -100 开头）。
                  </span>
                </div>
              </div>
            </div>

            <div v-else class="flex items-center gap-2">
              <span>❌</span>
              <span class="font-medium">
                {{ telegramRelayStatus.error || '连接失败，请检查 Bot Token 是否正确' }}
              </span>
            </div>
          </div>

          <!-- Action Buttons -->
          <div class="flex flex-wrap items-center gap-3 pt-2">
            <NextButton
              blue
              :is-loading="isSavingTelegramRelay"
              type="submit"
            >
              {{ $t('GENERAL_SETTINGS.FORM.TELEGRAM_RELAY.UPDATE_BUTTON') }}
            </NextButton>
            <NextButton
              variant="outline"
              color="slate"
              :is-loading="isSettingUpTelegramWebhook"
              type="button"
              @click="setupTelegramWebhook"
            >
              {{ $t('GENERAL_SETTINGS.FORM.TELEGRAM_RELAY.SETUP_WEBHOOK') }}
            </NextButton>
            <NextButton
              ghost
              color="slate"
              :is-loading="isTestingTelegramConnection"
              type="button"
              @click="() => testTelegramConnection(false)"
            >
              {{ $t('GENERAL_SETTINGS.FORM.TELEGRAM_RELAY.TEST_CONNECTION') }}
            </NextButton>
          </div>
        </form>
      </div>
    </SectionLayout>
    <AccountId />
    <div v-if="!uiFlags.isFetchingItem && isOnChatwootCloud">
      <AccountDelete />
    </div>
    <BuildInfo />
  </div>
</template>
