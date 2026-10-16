<script>
import { mapGetters } from 'vuex';
import FilterInputBox from 'dashboard/components/widgets/FilterInput/Index.vue';
import AutomationActionInput from 'dashboard/components/widgets/AutomationActionInput.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import { useAutomation } from 'dashboard/composables/useAutomation';
import { validateAutomation } from 'dashboard/helper/validations';
import {
  generateAutomationPayload,
  getAttributes,
  getInputType,
  getOperators,
  getCustomAttributeType,
  showActionInput,
} from 'dashboard/helper/automationHelper';
import { AUTOMATION_RULE_EVENTS, AUTOMATION_ACTION_TYPES } from './constants';
import { AUTOMATION_TEMPLATES } from './AutomationTemplates';

const start_value = {
  name: null,
  description: null,
  event_name: 'conversation_created',
  conditions: [
    {
      attribute_key: 'status',
      filter_operator: 'equal_to',
      values: '',
      query_operator: 'and',
      custom_attribute_type: '',
    },
  ],
  actions: [
    {
      action_name: 'assign_agent',
      action_params: [],
    },
  ],
};

export default {
  components: {
    FilterInputBox,
    AutomationActionInput,
    NextButton,
  },
  props: {
    onClose: {
      type: Function,
      default: () => {},
    },
  },
  emits: ['saveAutomation'],
  setup() {
    const {
      automation,
      automationTypes,
      onEventChange,
      getConditionDropdownValues,
      appendNewCondition,
      appendNewAction,
      removeFilter,
      removeAction,
      resetFilter,
      resetAction,
      getActionDropdownValues,
      manifestCustomAttributes,
    } = useAutomation(start_value);
    return {
      automation,
      automationTypes,
      onEventChange,
      getConditionDropdownValues,
      appendNewCondition,
      appendNewAction,
      removeFilter,
      removeAction,
      resetFilter,
      resetAction,
      getActionDropdownValues,
      manifestCustomAttributes,
    };
  },
  data() {
    return {
      automationRuleEvent: AUTOMATION_RULE_EVENTS[0].key,
      automationMutated: false,
      show: true,
      showDeleteConfirmationModal: false,
      allCustomAttributes: [],
      mode: 'create',
      errors: {},
      showTemplates: true,
      selectedTemplateId: null,
      templates: AUTOMATION_TEMPLATES,
    };
  },
  computed: {
    ...mapGetters({
      accountId: 'getCurrentAccountId',
      isFeatureEnabledonAccount: 'accounts/isFeatureEnabledonAccount',
    }),
    automationRuleEvents() {
      return AUTOMATION_RULE_EVENTS.map(event => ({
        ...event,
        value: this.$t(`AUTOMATION.EVENTS.${event.value}`),
      }));
    },
    hasAutomationMutated() {
      if (
        this.automation?.conditions?.[0]?.values ||
        this.automation?.actions?.[0]?.action_params?.length
      ) {
        return true;
      }
      return false;
    },
    automationActionTypes() {
      const actionTypes = this.isFeatureEnabled('sla')
        ? AUTOMATION_ACTION_TYPES
        : AUTOMATION_ACTION_TYPES.filter(({ key }) => key !== 'add_sla');

      return actionTypes.map(action => ({
        ...action,
        label: this.$t(`AUTOMATION.ACTIONS.${action.label}`),
      }));
    },
    currentEventLabel() {
      const map = {
        conversation_created: '新会话创建 (Conversation Created)',
        conversation_updated: '会话更新 (Conversation Updated)',
        message_created: '收到新消息 (Message Created)',
        conversation_opened: '会话重新开启 (Conversation Opened)',
      };
      return map[this.automation?.event_name] || this.automation?.event_name || '未选择事件';
    },
    currentConditionsSummary() {
      const count = this.automation?.conditions?.length || 0;
      return `${count} 条判定条件`;
    },
    currentActionsSummary() {
      const actions = this.automation?.actions || [];
      if (!actions.length) return '未配置动作';
      const labels = actions.map(act => {
        const found = this.automationActionTypes.find(a => a.key === act.action_name);
        return found ? found.label : act.action_name;
      });
      if (labels.length <= 2) {
        return labels.join(' + ');
      }
      return `${labels.slice(0, 2).join(' + ')} 等${labels.length}项`;
    },
    eventDescription() {
      const map = {
        conversation_created: '当访客/客户在任意收件箱发起全新会话时触发',
        conversation_updated: '当已有会话的状态、自定义属性或分配发生变更时触发',
        message_created: '当收到客户发送的消息或会话中有新消息时触发',
        conversation_opened: '当会话被重新标记为开启（Open）时触发',
      };
      return map[this.automation?.event_name] || '';
    },
  },
  mounted() {
    this.$store.dispatch('inboxes/get');
    this.$store.dispatch('agents/get');
    this.$store.dispatch('contacts/get');
    this.$store.dispatch('teams/get');
    this.$store.dispatch('labels/get');
    this.$store.dispatch('campaigns/get');
    this.allCustomAttributes = this.$store.getters['attributes/getAttributes'];
    this.manifestCustomAttributes();
  },
  methods: {
    getAttributes,
    getInputType,
    getOperators,
    getCustomAttributeType,
    showActionInput,
    isFeatureEnabled(flag) {
      return this.isFeatureEnabledonAccount(this.accountId, flag);
    },
    applyTemplate(tpl) {
      this.selectedTemplateId = tpl.id;
      const cloned = JSON.parse(JSON.stringify(tpl.rule));
      this.automation.name = cloned.name;
      this.automation.description = cloned.description;
      this.automation.event_name = cloned.event_name;
      this.automation.conditions = cloned.conditions;
      this.automation.actions = cloned.actions;
      this.errors = {};
    },
    emitSaveAutomation() {
      this.errors = validateAutomation(this.automation);
      if (Object.keys(this.errors).length === 0) {
        const automation = generateAutomationPayload(this.automation);
        this.$emit('saveAutomation', automation, this.mode);
      }
    },
    getTranslatedAttributes(type, event) {
      return getAttributes(type, event).map(attribute => {
        const skipTranslation =
          attribute.customAttributeType ||
          [
            'contact_custom_attribute',
            'conversation_custom_attribute',
          ].includes(attribute.key);

        return {
          ...attribute,
          name: skipTranslation
            ? attribute.name
            : this.$t(`AUTOMATION.ATTRIBUTES.${attribute.name}`),
        };
      });
    },
  },
};
</script>

<template>
  <div class="overflow-y-auto max-h-[85vh] p-1">
    <!-- Header -->
    <div class="mb-5 border-b border-n-strong pb-4">
      <div class="flex items-center justify-between">
        <div>
          <h2 class="text-xl font-bold text-n-slate-12 flex items-center gap-2">
            <span class="i-lucide-sparkles text-n-brand size-6" />
            可视化自动化规则配置
          </h2>
          <p class="text-xs text-n-slate-11 mt-1">
            通过“触发时机 ➔ 匹配条件 ➔ 自动执行”可视化流程卡片，无需复杂代码即可轻松构建客户服务自动化
          </p>
        </div>
        <div class="flex items-center gap-2">
          <button
            type="button"
            class="text-xs px-3 py-1.5 rounded-lg border border-n-strong hover:bg-n-slate-3 dark:hover:bg-n-solid-3 text-n-slate-12 flex items-center gap-1.5 transition-colors"
            @click="showTemplates = !showTemplates"
          >
            <span
              :class="showTemplates ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
              class="size-3.5"
            />
            {{ showTemplates ? '收起场景模板' : '展开场景模板' }}
          </button>
        </div>
      </div>

      <!-- Template Presets Grid -->
      <div v-if="showTemplates" class="mt-4 pt-4 border-t border-dashed border-n-strong">
        <div class="text-xs font-semibold text-n-slate-11 uppercase tracking-wider mb-2.5 flex items-center gap-1.5">
          <span class="i-lucide-layers size-3.5 text-n-brand" />
          点击下方场景模板，一键自动填充配置：
        </div>
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-2.5">
          <div
            v-for="tpl in templates"
            :key="tpl.id"
            :class="[
              'group relative p-3 rounded-xl border text-left cursor-pointer transition-all duration-150 flex flex-col justify-between',
              selectedTemplateId === tpl.id
                ? 'border-n-brand ring-2 ring-n-brand/30 bg-n-brand/5 dark:bg-n-brand/10'
                : 'border-n-strong hover:border-n-brand/60 bg-white dark:bg-n-solid-2 hover:shadow-sm'
            ]"
            @click="applyTemplate(tpl)"
          >
            <div>
              <div class="flex items-center justify-between mb-1.5">
                <div class="flex items-center gap-1.5">
                  <span :class="[tpl.icon, 'size-4 text-n-brand']" />
                  <span class="text-xs font-bold text-n-slate-12">{{ tpl.title }}</span>
                </div>
                <span
                  :class="[
                    'text-[10px] px-1.5 py-0.5 rounded-full font-medium',
                    tpl.badgeColor === 'blue' ? 'bg-blue-100 text-blue-700 dark:bg-blue-900/40 dark:text-blue-300' : '',
                    tpl.badgeColor === 'teal' ? 'bg-teal-100 text-teal-700 dark:bg-teal-900/40 dark:text-teal-300' : '',
                    tpl.badgeColor === 'purple' ? 'bg-purple-100 text-purple-700 dark:bg-purple-900/40 dark:text-purple-300' : '',
                    tpl.badgeColor === 'amber' ? 'bg-amber-100 text-amber-700 dark:bg-amber-900/40 dark:text-amber-300' : '',
                    tpl.badgeColor === 'indigo' ? 'bg-indigo-100 text-indigo-700 dark:bg-indigo-900/40 dark:text-indigo-300' : '',
                    tpl.badgeColor === 'emerald' ? 'bg-emerald-100 text-emerald-700 dark:bg-emerald-900/40 dark:text-emerald-300' : '',
                  ]"
                >
                  {{ tpl.badge }}
                </span>
              </div>
              <p class="text-[11px] text-n-slate-11 line-clamp-2 leading-relaxed">
                {{ tpl.desc }}
              </p>
            </div>
            <div class="mt-2.5 flex items-center justify-between text-[11px] text-n-brand font-medium">
              <span class="flex items-center gap-1">
                <span class="i-lucide-check-circle-2 size-3" />
                {{ selectedTemplateId === tpl.id ? '当前已应用' : '套用此模板' }}
              </span>
              <span class="i-lucide-arrow-right size-3 opacity-0 group-hover:opacity-100 transition-opacity" />
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Visual Pipeline Preview Bar -->
    <div class="p-3 mb-6 rounded-xl bg-n-slate-2 dark:bg-n-solid-1 border border-n-strong">
      <div class="flex items-center justify-between text-[11px] font-medium text-n-slate-11 mb-2">
        <span class="flex items-center gap-1">
          <span class="i-lucide-activity size-3.5 text-n-brand" />
          自动化流程全景看板
        </span>
        <span class="text-n-slate-10">实时反映当前规则流水线</span>
      </div>
      <div class="grid grid-cols-1 md:grid-cols-3 gap-2 items-center">
        <!-- Node 1 -->
        <div class="flex items-center gap-2.5 p-2 rounded-lg bg-white dark:bg-n-solid-2 border border-n-strong">
          <div class="size-7 rounded-lg bg-blue-50 dark:bg-blue-950 flex items-center justify-center flex-shrink-0 text-blue-600 dark:text-blue-400">
            <span class="i-lucide-zap size-4" />
          </div>
          <div class="min-w-0">
            <div class="text-[10px] text-n-slate-10 font-bold uppercase tracking-wider">节点 1 · 触发事件</div>
            <div class="text-xs font-semibold text-n-slate-12 truncate">{{ currentEventLabel }}</div>
          </div>
        </div>

        <!-- Node 2 -->
        <div class="flex items-center gap-2.5 p-2 rounded-lg bg-white dark:bg-n-solid-2 border border-n-strong">
          <div class="size-7 rounded-lg bg-amber-50 dark:bg-amber-950 flex items-center justify-center flex-shrink-0 text-amber-600 dark:text-amber-400">
            <span class="i-lucide-filter size-4" />
          </div>
          <div class="min-w-0">
            <div class="text-[10px] text-n-slate-10 font-bold uppercase tracking-wider">节点 2 · 匹配条件</div>
            <div class="text-xs font-semibold text-n-slate-12 truncate">{{ currentConditionsSummary }}</div>
          </div>
        </div>

        <!-- Node 3 -->
        <div class="flex items-center gap-2.5 p-2 rounded-lg bg-white dark:bg-n-solid-2 border border-n-strong">
          <div class="size-7 rounded-lg bg-emerald-50 dark:bg-emerald-950 flex items-center justify-center flex-shrink-0 text-emerald-600 dark:text-emerald-400">
            <span class="i-lucide-play size-4" />
          </div>
          <div class="min-w-0">
            <div class="text-[10px] text-n-slate-10 font-bold uppercase tracking-wider">节点 3 · 自动执行</div>
            <div class="text-xs font-semibold text-n-slate-12 truncate">{{ currentActionsSummary }}</div>
          </div>
        </div>
      </div>
    </div>

    <!-- Basic Info Card -->
    <div class="p-4 rounded-xl bg-white dark:bg-n-solid-2 border border-n-strong mb-5 shadow-sm">
      <div class="flex items-center gap-2 mb-3">
        <span class="i-lucide-file-text size-4 text-n-slate-11" />
        <span class="text-xs font-bold uppercase tracking-wider text-n-slate-11">规则基础信息</span>
      </div>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div>
          <woot-input
            v-model="automation.name"
            :label="$t('AUTOMATION.ADD.FORM.NAME.LABEL')"
            type="text"
            :class="{ error: errors.name }"
            :error="errors.name ? $t('AUTOMATION.ADD.FORM.NAME.ERROR') : ''"
            :placeholder="$t('AUTOMATION.ADD.FORM.NAME.PLACEHOLDER')"
          />
        </div>
        <div>
          <woot-input
            v-model="automation.description"
            :label="$t('AUTOMATION.ADD.FORM.DESC.LABEL')"
            type="text"
            :class="{ error: errors.description }"
            :error="errors.description ? $t('AUTOMATION.ADD.FORM.DESC.ERROR') : ''"
            :placeholder="$t('AUTOMATION.ADD.FORM.DESC.PLACEHOLDER')"
          />
        </div>
      </div>
    </div>

    <!-- Step 1 Card: 触发事件 (When) -->
    <div class="rounded-xl border border-n-strong bg-white dark:bg-n-solid-2 shadow-sm overflow-hidden">
      <div class="p-4 bg-n-slate-2 dark:bg-n-solid-1 border-b border-n-strong flex items-center justify-between">
        <div class="flex items-center gap-3">
          <span class="px-2.5 py-1 rounded-md text-xs font-bold bg-blue-100 text-blue-700 dark:bg-blue-900/60 dark:text-blue-300">
            步骤 1
          </span>
          <div>
            <h3 class="text-sm font-bold text-n-slate-12 flex items-center gap-1.5">
              <span class="i-lucide-zap size-4 text-blue-600 dark:text-blue-400" />
              {{ $t('AUTOMATION.ADD.FORM.EVENT.LABEL') }}
            </h3>
            <p class="text-xs text-n-slate-11">当发生此系统事件时，自动化流程将被唤醒并开始检查条件</p>
          </div>
        </div>
      </div>
      <div class="p-4">
        <label :class="{ error: errors.event_name }" class="block">
          <select
            v-model="automation.event_name"
            class="m-0 w-full rounded-lg border border-n-strong bg-white dark:bg-n-solid-2 text-n-slate-12 p-2.5 text-sm font-medium focus:ring-2 focus:ring-n-brand/30"
            @change="onEventChange(automation)"
          >
            <option
              v-for="event in automationRuleEvents"
              :key="event.key"
              :value="event.key"
            >
              {{ event.value }}
            </option>
          </select>
          <span v-if="errors.event_name" class="message text-xs text-red-500 mt-1 block">
            {{ $t('AUTOMATION.ADD.FORM.EVENT.ERROR') }}
          </span>
        </label>
        <div class="mt-2 text-xs text-n-slate-11 flex items-center gap-1.5 bg-n-slate-1 dark:bg-n-solid-1 p-2 rounded-lg border border-n-weak">
          <span class="i-lucide-info size-3.5 text-blue-500 flex-shrink-0" />
          <span>{{ eventDescription }}</span>
        </div>
        <p
          v-if="hasAutomationMutated"
          class="text-xs text-right text-n-teal-10 pt-2"
        >
          {{ $t('AUTOMATION.FORM.RESET_MESSAGE') }}
        </p>
      </div>
    </div>

    <!-- Visual Arrow Down -->
    <div class="flex items-center justify-center my-3">
      <div class="flex flex-col items-center text-n-slate-9 dark:text-n-slate-10">
        <div class="w-0.5 h-3 bg-n-strong" />
        <span class="i-lucide-arrow-down size-4 text-n-slate-10" />
      </div>
    </div>

    <!-- Step 2 Card: 判定条件 (If) -->
    <div class="rounded-xl border border-n-strong bg-white dark:bg-n-solid-2 shadow-sm overflow-hidden">
      <div class="p-4 bg-n-slate-2 dark:bg-n-solid-1 border-b border-n-strong flex items-center justify-between">
        <div class="flex items-center gap-3">
          <span class="px-2.5 py-1 rounded-md text-xs font-bold bg-amber-100 text-amber-700 dark:bg-amber-900/60 dark:text-amber-300">
            步骤 2
          </span>
          <div>
            <h3 class="text-sm font-bold text-n-slate-12 flex items-center gap-1.5">
              <span class="i-lucide-filter size-4 text-amber-600 dark:text-amber-400" />
              {{ $t('AUTOMATION.ADD.FORM.CONDITIONS.LABEL') }}
            </h3>
            <p class="text-xs text-n-slate-11">设置过滤条件。只有完全符合全部或部分条件的会话或消息，才会继续向下执行</p>
          </div>
        </div>
      </div>
      <div class="p-4">
        <div class="w-full space-y-3">
          <FilterInputBox
            v-for="(condition, i) in automation.conditions"
            :key="i"
            v-model="automation.conditions[i]"
            :filter-attributes="getTranslatedAttributes(automationTypes, automation.event_name)"
            :input-type="getInputType(allCustomAttributes, automationTypes, automation, automation.conditions[i].attribute_key)"
            :operators="getOperators(allCustomAttributes, automationTypes, automation, mode, automation.conditions[i].attribute_key)"
            :dropdown-values="getConditionDropdownValues(automation.conditions[i].attribute_key)"
            :show-query-operator="i !== automation.conditions.length - 1"
            :custom-attribute-type="getCustomAttributeType(automationTypes, automation, automation.conditions[i].attribute_key)"
            :error-message="errors[`condition_${i}`] ? $t(`AUTOMATION.ERRORS.${errors[`condition_${i}`]}`) : ''"
            @reset-filter="resetFilter(i, automation.conditions[i])"
            @remove-filter="removeFilter(i)"
          />
        </div>
        <div class="mt-4 pt-3 border-t border-n-strong flex items-center justify-between">
          <NextButton
            icon="i-lucide-plus"
            blue
            faded
            sm
            :label="$t('AUTOMATION.ADD.CONDITION_BUTTON_LABEL')"
            @click="appendNewCondition"
          />
          <span class="text-xs text-n-slate-10">可添加多条条件，并在条件右侧选择“与(AND) / 或(OR)”</span>
        </div>
      </div>
    </div>

    <!-- Visual Arrow Down -->
    <div class="flex items-center justify-center my-3">
      <div class="flex flex-col items-center text-n-slate-9 dark:text-n-slate-10">
        <div class="w-0.5 h-3 bg-n-strong" />
        <span class="i-lucide-arrow-down size-4 text-n-slate-10" />
      </div>
    </div>

    <!-- Step 3 Card: 执行动作 (Then) -->
    <div class="rounded-xl border border-n-strong bg-white dark:bg-n-solid-2 shadow-sm overflow-hidden mb-6">
      <div class="p-4 bg-n-slate-2 dark:bg-n-solid-1 border-b border-n-strong flex items-center justify-between">
        <div class="flex items-center gap-3">
          <span class="px-2.5 py-1 rounded-md text-xs font-bold bg-emerald-100 text-emerald-700 dark:bg-emerald-900/60 dark:text-emerald-300">
            步骤 3
          </span>
          <div>
            <h3 class="text-sm font-bold text-n-slate-12 flex items-center gap-1.5">
              <span class="i-lucide-play size-4 text-emerald-600 dark:text-emerald-400" />
              {{ $t('AUTOMATION.ADD.FORM.ACTIONS.LABEL') }}
            </h3>
            <p class="text-xs text-n-slate-11">当满足上述条件时，系统将自动依次执行以下操作</p>
          </div>
        </div>
      </div>
      <div class="p-4">
        <div class="w-full space-y-3">
          <AutomationActionInput
            v-for="(action, i) in automation.actions"
            :key="i"
            v-model="automation.actions[i]"
            :action-types="automationActionTypes"
            :dropdown-values="getActionDropdownValues(automation.actions[i].action_name)"
            :show-action-input="showActionInput(automationActionTypes, automation.actions[i].action_name)"
            :error-message="errors[`action_${i}`] ? $t(`AUTOMATION.ERRORS.${errors[`action_${i}`]}`) : ''"
            @reset-action="resetAction(i)"
            @remove-action="removeAction(i)"
          />
        </div>
        <div class="mt-4 pt-3 border-t border-n-strong flex items-center justify-between">
          <NextButton
            icon="i-lucide-plus"
            blue
            faded
            sm
            :label="$t('AUTOMATION.ADD.ACTION_BUTTON_LABEL')"
            @click="appendNewAction"
          />
          <span class="text-xs text-n-slate-10">支持同时配置多个动作（例如：打标签 + 分配团队 + 自动回复）</span>
        </div>
      </div>
    </div>

    <!-- Footer Action Buttons -->
    <div class="sticky bottom-0 bg-white dark:bg-n-solid-2 py-3 px-1 border-t border-n-strong flex items-center justify-between">
      <div class="text-xs text-n-slate-11">
        配置完成后点击“保存规则”，自动化将在新进事件中立即生效
      </div>
      <div class="flex items-center gap-2">
        <NextButton
          faded
          slate
          type="reset"
          :label="$t('AUTOMATION.ADD.CANCEL_BUTTON_TEXT')"
          @click.prevent="onClose"
        />
        <NextButton
          solid
          blue
          type="submit"
          :label="$t('AUTOMATION.ADD.SUBMIT')"
          @click="emitSaveAutomation"
        />
      </div>
    </div>
  </div>
</template>
