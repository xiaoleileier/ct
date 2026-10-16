<script>
import AutomationActionTeamMessageInput from './AutomationActionTeamMessageInput.vue';
import AutomationActionFileInput from './AutomationFileInput.vue';
import WootMessageEditor from 'dashboard/components/widgets/WootWriter/Editor.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

export default {
  components: {
    AutomationActionTeamMessageInput,
    AutomationActionFileInput,
    WootMessageEditor,
    NextButton,
  },
  props: {
    modelValue: {
      type: Object,
      default: () => null,
    },
    actionTypes: {
      type: Array,
      default: () => [],
    },
    dropdownValues: {
      type: Array,
      default: () => [],
    },
    errorMessage: {
      type: String,
      default: '',
    },
    showActionInput: {
      type: Boolean,
      default: true,
    },
    initialFileName: {
      type: String,
      default: '',
    },
    isMacro: {
      type: Boolean,
      default: false,
    },
  },
  emits: ['update:modelValue', 'input', 'removeAction', 'resetAction'],
  computed: {
    action_name: {
      get() {
        if (!this.modelValue) return null;
        return this.modelValue.action_name;
      },
      set(value) {
        const payload = this.modelValue || {};
        this.$emit('update:modelValue', { ...payload, action_name: value });
        this.$emit('input', { ...payload, action_name: value });
      },
    },
    action_params: {
      get() {
        if (!this.modelValue) return null;
        return this.modelValue.action_params;
      },
      set(value) {
        const payload = this.modelValue || {};
        this.$emit('update:modelValue', { ...payload, action_params: value });
        this.$emit('input', { ...payload, action_params: value });
      },
    },
    inputType() {
      return this.actionTypes.find(action => action.key === this.action_name)
        .inputType;
    },
    actionInputStyles() {
      return {
        'has-error': this.errorMessage,
        'is-a-macro': this.isMacro,
      };
    },
    castMessageVmodel: {
      get() {
        if (Array.isArray(this.action_params)) {
          return this.action_params[0];
        }
        return this.action_params;
      },
      set(value) {
        this.action_params = value;
      },
    },
    menuTitle: {
      get() {
        const param = Array.isArray(this.action_params)
          ? this.action_params[0]
          : this.action_params;
        return param?.title || '';
      },
      set(val) {
        const param = Array.isArray(this.action_params)
          ? this.action_params[0] || {}
          : this.action_params || {};
        this.action_params = [{ ...param, title: val }];
      },
    },
    menuOptions: {
      get() {
        const param = Array.isArray(this.action_params)
          ? this.action_params[0]
          : this.action_params;
        return param?.options || '';
      },
      set(val) {
        const param = Array.isArray(this.action_params)
          ? this.action_params[0] || {}
          : this.action_params || {};
        this.action_params = [{ ...param, options: val }];
      },
    },
    parsedMenuOptions() {
      if (!this.menuOptions) return [];
      return this.menuOptions
        .split(/[,，\n]/)
        .map(s => s.trim())
        .filter(Boolean);
    },
  },
  methods: {
    removeAction() {
      this.$emit('removeAction');
    },
    resetAction() {
      this.$emit('resetAction');
    },
  },
};
</script>

<template>
  <div class="filter" :class="actionInputStyles">
    <div class="filter-inputs">
      <select
        v-model="action_name"
        class="action__question"
        :class="{ 'full-width': !showActionInput }"
        @change="resetAction()"
      >
        <option
          v-for="attribute in actionTypes"
          :key="attribute.key"
          :value="attribute.key"
        >
          {{ attribute.label }}
        </option>
      </select>
      <div v-if="showActionInput" class="filter__answer--wrap">
        <div v-if="inputType" class="w-full">
          <div
            v-if="inputType === 'search_select'"
            class="multiselect-wrap--small"
          >
            <multiselect
              v-model="action_params"
              track-by="id"
              label="name"
              :placeholder="$t('FORMS.MULTISELECT.SELECT')"
              selected-label
              :select-label="$t('FORMS.MULTISELECT.ENTER_TO_SELECT')"
              deselect-label=""
              :max-height="160"
              :options="dropdownValues"
              :allow-empty="false"
              :option-height="104"
            >
              <template #noOptions>
                {{ $t('FORMS.MULTISELECT.NO_OPTIONS') }}
              </template>
            </multiselect>
          </div>
          <div
            v-else-if="inputType === 'multi_select'"
            class="multiselect-wrap--small"
          >
            <multiselect
              v-model="action_params"
              track-by="id"
              label="name"
              :placeholder="$t('FORMS.MULTISELECT.SELECT')"
              multiple
              selected-label
              :select-label="$t('FORMS.MULTISELECT.ENTER_TO_SELECT')"
              deselect-label=""
              :max-height="160"
              :options="dropdownValues"
              :allow-empty="false"
              :option-height="104"
            >
              <template #noOptions>
                {{ $t('FORMS.MULTISELECT.NO_OPTIONS') }}
              </template>
            </multiselect>
          </div>
          <input
            v-else-if="inputType === 'email'"
            v-model="action_params"
            type="email"
            class="answer--text-input"
            :placeholder="$t('AUTOMATION.ACTION.EMAIL_INPUT_PLACEHOLDER')"
          />
          <input
            v-else-if="inputType === 'url'"
            v-model="action_params"
            type="url"
            class="answer--text-input"
            :placeholder="$t('AUTOMATION.ACTION.URL_INPUT_PLACEHOLDER')"
          />
          <AutomationActionFileInput
            v-if="inputType === 'attachment'"
            v-model="action_params"
            :initial-file-name="initialFileName"
          />
        </div>
      </div>
      <NextButton
        v-if="!isMacro"
        icon="i-lucide-x"
        slate
        ghost
        class="flex-shrink-0"
        @click="removeAction"
      />
    </div>
    <AutomationActionTeamMessageInput
      v-if="inputType === 'team_message'"
      v-model="action_params"
      :teams="dropdownValues"
    />
    <WootMessageEditor
      v-if="inputType === 'textarea'"
      v-model="castMessageVmodel"
      rows="4"
      enable-variables
      :placeholder="$t('AUTOMATION.ACTION.TEAM_MESSAGE_INPUT_PLACEHOLDER')"
      class="action-message"
    />
    <div
      v-if="inputType === 'interactive_menu'"
      class="mt-3 p-3.5 rounded-xl bg-n-slate-1 dark:bg-n-solid-1 border border-n-strong space-y-3"
    >
      <div>
        <label class="text-xs font-bold text-n-slate-12 block mb-1">
          📌 菜单引导语 / 提示文本：
        </label>
        <input
          v-model="menuTitle"
          type="text"
          class="w-full text-xs rounded-lg border border-n-strong bg-white dark:bg-n-solid-2 p-2.5 text-n-slate-12 focus:ring-2 focus:ring-n-brand/30"
          placeholder="例如：您好！欢迎使用在线客服，请选择您想了解的业务："
        />
      </div>
      <div>
        <label class="text-xs font-bold text-n-slate-12 block mb-1">
          🔘 可点击按钮选项（多个按钮用逗号或换行分隔）：
        </label>
        <input
          v-model="menuOptions"
          type="text"
          class="w-full text-xs rounded-lg border border-n-strong bg-white dark:bg-n-solid-2 p-2.5 text-n-slate-12 focus:ring-2 focus:ring-n-brand/30"
          placeholder="例如：业务收费方案, 常见使用问题, 转接人工客服"
        />
      </div>
      <div v-if="parsedMenuOptions.length" class="pt-2 border-t border-n-strong">
        <div class="text-[11px] text-n-slate-10 mb-1.5 font-medium flex items-center gap-1">
          <span class="i-lucide-eye size-3 text-n-brand" />
          访客端实时预览效果：
        </div>
        <div class="text-xs text-n-slate-12 mb-2 font-medium">
          {{ menuTitle || '请选择您想了解的内容：' }}
        </div>
        <div class="flex flex-wrap gap-1.5">
          <span
            v-for="(opt, idx) in parsedMenuOptions"
            :key="idx"
            class="px-3 py-1 rounded-full text-xs font-medium border border-n-brand text-n-brand bg-n-brand/5 dark:bg-n-brand/10 flex items-center gap-1.5 shadow-sm"
          >
            <span class="size-1.5 rounded-full bg-n-brand inline-block" />
            {{ opt }}
          </span>
        </div>
      </div>
    </div>
    <p v-if="errorMessage" class="filter-error">
      {{ errorMessage }}
    </p>
  </div>
</template>

<style lang="scss" scoped>
.filter {
  @apply bg-n-background p-2 border border-solid border-n-strong dark:border-n-strong rounded-lg mb-2;

  &.is-a-macro {
    @apply mb-0 bg-n-background dark:bg-n-solid-1 p-0 border-0 rounded-none;
  }
}

.no-margin-bottom {
  @apply mb-0;
}

.filter.has-error {
  @apply bg-n-ruby-8/20 border-n-ruby-5 dark:border-n-ruby-5;

  &.is-a-macro {
    @apply bg-transparent;
  }
}

.filter-inputs {
  @apply flex gap-1;
}

.filter-error {
  @apply text-n-ruby-9 dark:text-n-ruby-9 block my-1 mx-0;
}

.action__question,
.filter__operator {
  @apply mb-0 mr-1;
}

.action__question {
  @apply max-w-[50%];
}

.action__question.full-width {
  @apply max-w-full;
}

.filter__answer--wrap {
  @apply max-w-[50%] flex-grow mr-1 flex w-full items-center justify-start;

  input {
    @apply mb-0;
  }
}
.filter__answer {
  &.answer--text-input {
    @apply mb-0;
  }
}

.filter__join-operator-wrap {
  @apply relative z-20 m-0;
}

.filter__join-operator {
  @apply flex items-center justify-center relative my-2.5 mx-0;

  .operator__line {
    @apply absolute w-full border-b border-solid border-n-weak;
  }

  .operator__select {
    margin-bottom: 0 !important;
    @apply relative w-auto;
  }
}

.multiselect {
  @apply mb-0;
}
.action-message {
  @apply mt-2 mx-0 mb-0;
}
// Prosemirror does not have a native way of hiding the menu bar, hence
::v-deep .ProseMirror-menubar {
  @apply hidden;
}
</style>
