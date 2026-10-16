<script setup>
import { computed } from 'vue';
import { getLanguageName } from 'dashboard/components/widgets/conversation/advancedFilterItems/languages';
import ContactDetailsItem from './ContactDetailsItem.vue';
import CustomAttributes from './customAttributes/CustomAttributes.vue';

const props = defineProps({
  conversationAttributes: {
    type: Object,
    default: () => ({}),
  },
  contactAttributes: {
    type: Object,
    default: () => ({}),
  },
});

const referer = computed(() => props.conversationAttributes.referer);
const initiatedAt = computed(
  () => props.conversationAttributes.initiated_at?.timestamp
);

const browserInfo = computed(() => props.conversationAttributes.browser);

const browserName = computed(() => {
  if (!browserInfo.value) return '';
  const { browser_name: name = '', browser_version: version = '' } =
    browserInfo.value;
  return `${name} ${version}`;
});

const browserLanguage = computed(() =>
  getLanguageName(props.conversationAttributes.browser_language)
);

const platformName = computed(() => {
  if (!browserInfo.value) return '';
  const { platform_name: name = '', platform_version: version = '' } =
    browserInfo.value;
  return `${name} ${version}`;
});

const createdAtIp = computed(() => props.contactAttributes.created_at_ip);

const staticElements = computed(() =>
  [
    {
      content: initiatedAt,
      title: 'CONTACT_PANEL.INITIATED_AT',
      key: 'static-initiated-at',
      type: 'static_attribute',
    },
    {
      content: browserLanguage,
      title: 'CONTACT_PANEL.BROWSER_LANGUAGE',
      key: 'static-browser-language',
      type: 'static_attribute',
    },
    {
      content: referer,
      title: 'CONTACT_PANEL.INITIATED_FROM',
      key: 'static-referer',
      type: 'static_attribute',
    },
    {
      content: browserName,
      title: 'CONTACT_PANEL.BROWSER',
      key: 'static-browser',
      type: 'static_attribute',
    },
    {
      content: platformName,
      title: 'CONTACT_PANEL.OS',
      key: 'static-platform',
      type: 'static_attribute',
    },
    {
      content: createdAtIp,
      title: 'CONTACT_PANEL.IP_ADDRESS',
      key: 'static-ip-address',
      type: 'static_attribute',
    },
  ].filter(attribute => !!attribute.content.value)
);
const trafficSourceInfo = computed(() => {
  const refUrl = referer.value || '';
  if (!refUrl) {
    return {
      source: '直接访问 / 书签',
      icon: 'i-lucide-globe',
      color: 'text-n-slate-11',
      utmSource: null,
      utmCampaign: null,
      utmMedium: null,
      utmTerm: null,
    };
  }

  try {
    const url = new URL(refUrl, 'https://unknown.com');
    const host = url.hostname.toLowerCase();
    const searchParams = url.searchParams;

    let source = '外部网页引流';
    let icon = 'i-lucide-external-link';
    let color = 'text-blue-500';

    if (host.includes('baidu.')) {
      source = '百度搜索 (Baidu)';
      icon = 'i-lucide-search';
      color = 'text-blue-600';
    } else if (host.includes('google.')) {
      source = '谷歌搜索 (Google)';
      icon = 'i-lucide-search';
      color = 'text-emerald-600';
    } else if (host.includes('bing.')) {
      source = '必应搜索 (Bing)';
      icon = 'i-lucide-search';
      color = 'text-cyan-600';
    } else if (host.includes('douyin.') || host.includes('tiktok.')) {
      source = '抖音 / TikTok 推广';
      icon = 'i-lucide-video';
      color = 'text-pink-600';
    } else if (host.includes('xiaohongshu.') || host.includes('xhslink.')) {
      source = '小红书引流';
      icon = 'i-lucide-sparkles';
      color = 'text-red-600';
    } else if (host.includes('zhihu.')) {
      source = '知乎问答 / 文章';
      icon = 'i-lucide-book-open';
      color = 'text-blue-500';
    } else if (host.includes('weixin.') || host.includes('qq.')) {
      source = '微信 / QQ 生态';
      icon = 'i-lucide-message-circle';
      color = 'text-emerald-500';
    } else if (host.includes('weibo.')) {
      source = '微博推广';
      icon = 'i-lucide-share-2';
      color = 'text-red-500';
    }

    return {
      source,
      icon,
      color,
      hostname: host,
      utmSource: searchParams.get('utm_source'),
      utmMedium: searchParams.get('utm_medium'),
      utmCampaign: searchParams.get('utm_campaign'),
      utmTerm:
        searchParams.get('utm_term') ||
        searchParams.get('wd') ||
        searchParams.get('q'),
    };
  } catch (e) {
    return {
      source: '直接访问 / 未知来源',
      icon: 'i-lucide-globe',
      color: 'text-n-slate-11',
      utmSource: null,
      utmCampaign: null,
      utmMedium: null,
      utmTerm: null,
    };
  }
});
</script>

<template>
  <div class="conversation--details">
    <!-- 访客来源与足迹画像卡片 -->
    <div
      class="m-3 p-3 rounded-xl border border-n-weak bg-n-slate-1 dark:bg-n-solid-2 shadow-2xs"
    >
      <div
        class="flex items-center justify-between mb-2 pb-2 border-b border-n-weak"
      >
        <span
          class="text-xs font-bold text-n-slate-12 flex items-center gap-1.5"
        >
          <span
            :class="[
              trafficSourceInfo.icon,
              trafficSourceInfo.color,
              'size-3.5',
            ]"
          />
          访客来源与足迹画像
        </span>
        <span
          class="text-[11px] font-semibold text-n-brand px-1.5 py-0.5 rounded bg-n-brand/10"
        >
          {{ trafficSourceInfo.source }}
        </span>
      </div>

      <div class="space-y-1.5 text-xs">
        <div
          v-if="trafficSourceInfo.utmCampaign || trafficSourceInfo.utmSource"
          class="flex justify-between items-center text-n-slate-11"
        >
          <span>推广来源/活动:</span>
          <span class="font-medium text-n-slate-12">
            {{
              [trafficSourceInfo.utmSource, trafficSourceInfo.utmCampaign]
                .filter(Boolean)
                .join(' / ')
            }}
          </span>
        </div>
        <div
          v-if="trafficSourceInfo.utmTerm"
          class="flex justify-between items-center text-n-slate-11"
        >
          <span>搜索关键词:</span>
          <span class="font-medium text-amber-600 dark:text-amber-400">
            "{{ trafficSourceInfo.utmTerm }}"
          </span>
        </div>
        <div
          v-if="referer"
          class="flex flex-col gap-0.5 text-n-slate-11 pt-1 border-t border-n-weak/50"
        >
          <span class="text-[11px]">发起页面 URL:</span>
          <a
            :href="referer"
            target="_blank"
            rel="noopener noreferrer"
            class="text-n-brand hover:underline break-all line-clamp-2 text-[11px]"
          >
            {{ referer }}
          </a>
        </div>
      </div>
    </div>

    <CustomAttributes
      :static-elements="staticElements"
      attribute-class="conversation--attribute"
      attribute-from="conversation_panel"
      attribute-type="conversation_attribute"
    >
      <template #staticItem="{ element }">
        <ContactDetailsItem
          :key="element.title"
          :title="$t(element.title)"
          :value="element.content.value"
        >
          <a
            v-if="element.key === 'static-referer'"
            :href="element.content.value"
            rel="noopener noreferrer nofollow"
            target="_blank"
            class="text-n-brand"
          >
            {{ element.content.value }}
          </a>
        </ContactDetailsItem>
      </template>
    </CustomAttributes>
  </div>
</template>
