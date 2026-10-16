export const AUTOMATION_TEMPLATES = [
  {
    id: 'interactive_menu',
    icon: 'i-lucide-layout-grid',
    badge: '交互菜单',
    badgeColor: 'blue',
    title: '新会话自动发送可点击按钮菜单',
    desc: '客户打开新会话时，自动弹出带可点击按钮的业务导航菜单，客户点击选项即可自助办理',
    rule: {
      name: '新会话自动发送业务导航菜单',
      description: '客户发起新咨询时，自动发送可点击的交互式按钮菜单进行引导',
      event_name: 'conversation_created',
      conditions: [
        {
          attribute_key: 'status',
          filter_operator: 'equal_to',
          values: [{ id: 'open', name: 'Open' }],
          query_operator: 'and',
          custom_attribute_type: '',
        },
      ],
      actions: [
        {
          action_name: 'send_interactive_menu',
          action_params: [
            {
              title: '您好！欢迎使用在线客服，请选择您想了解的业务：',
              options: '业务收费方案, 常见使用问题, 转接人工客服',
            },
          ],
        },
      ],
    },
  },
  {
    id: 'keyword_reply',
    icon: 'i-lucide-message-circle',
    badge: '高频推荐',
    badgeColor: 'blue',
    title: '客户发送关键词自动回复',
    desc: '当客户消息包含指定关键词（如“价格、人工、收费”）时，自动回复预设消息',
    rule: {
      name: '关键词自动回复',
      description: '当客户消息中包含指定关键词时，自动发送设定回复内容',
      event_name: 'message_created',
      conditions: [
        {
          attribute_key: 'message_type',
          filter_operator: 'equal_to',
          values: { id: 'incoming', name: 'Incoming' },
          query_operator: 'and',
          custom_attribute_type: '',
        },
        {
          attribute_key: 'content',
          filter_operator: 'contains',
          values: '价格, 人工, 费用, 优惠',
          query_operator: 'and',
          custom_attribute_type: '',
        },
      ],
      actions: [
        {
          action_name: 'send_message',
          action_params: [
            '您好！感谢您的咨询。关于相关业务与价格方案，请稍候，我们马上为您服务！',
          ],
        },
      ],
    },
  },
  {
    id: 'auto_assign_agent',
    icon: 'i-lucide-user-check',
    badge: '快速流转',
    badgeColor: 'teal',
    title: '新对话自动分配给客服',
    desc: '当客户发起新会话时，自动分配给指定的专属客服专员',
    rule: {
      name: '新对话自动分配客服',
      description: '客户发起新咨询时，自动指派给专属客服接待',
      event_name: 'conversation_created',
      conditions: [
        {
          attribute_key: 'status',
          filter_operator: 'equal_to',
          values: [{ id: 'open', name: 'Open' }],
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
    },
  },
  {
    id: 'auto_assign_team',
    icon: 'i-lucide-users',
    badge: '团队协同',
    badgeColor: 'purple',
    title: '按渠道分流到指定团队',
    desc: '根据会话来源渠道或收件箱，自动转派给对应负责团队（如售后/售前组）',
    rule: {
      name: '按渠道自动分流团队',
      description: '新咨询创建时，自动分配到指定业务团队进行处理',
      event_name: 'conversation_created',
      conditions: [
        {
          attribute_key: 'status',
          filter_operator: 'equal_to',
          values: [{ id: 'open', name: 'Open' }],
          query_operator: 'and',
          custom_attribute_type: '',
        },
      ],
      actions: [
        {
          action_name: 'assign_team',
          action_params: [],
        },
      ],
    },
  },
  {
    id: 'auto_label',
    icon: 'i-lucide-tag',
    badge: '智能归类',
    badgeColor: 'amber',
    title: '根据咨询内容自动打标签',
    desc: '检测客户消息内容或来源，自动打上标签（如“高意向客户”、“常见问题”）',
    rule: {
      name: '咨询内容自动打标签',
      description: '对符合特征的新对话自动打上对应分类标签',
      event_name: 'conversation_created',
      conditions: [
        {
          attribute_key: 'status',
          filter_operator: 'equal_to',
          values: [{ id: 'open', name: 'Open' }],
          query_operator: 'and',
          custom_attribute_type: '',
        },
      ],
      actions: [
        {
          action_name: 'add_label',
          action_params: [],
        },
      ],
    },
  },
  {
    id: 'off_hours_prompt',
    icon: 'i-lucide-moon',
    badge: '服务保障',
    badgeColor: 'indigo',
    title: '非工作时间/超时温馨提示',
    desc: '客户发来新消息时，自动发送当前营业时间说明或忙碌等候提示语',
    rule: {
      name: '非工作时间/自动欢迎提示',
      description: '收到客户消息时自动发送营业时间与在线指引',
      event_name: 'message_created',
      conditions: [
        {
          attribute_key: 'message_type',
          filter_operator: 'equal_to',
          values: { id: 'incoming', name: 'Incoming' },
          query_operator: 'and',
          custom_attribute_type: '',
        },
      ],
      actions: [
        {
          action_name: 'send_message',
          action_params: [
            '您好！当前客服人员可能正在处理其他咨询。我们的工作时间为 9:00 - 18:00，请直接留言您的问题，我们看到后会第一时间回复！',
          ],
        },
      ],
    },
  },
  {
    id: 'auto_resolve_inactive',
    icon: 'i-lucide-check-circle-2',
    badge: '自动闭环',
    badgeColor: 'emerald',
    title: '超时未响应自动关闭会话',
    desc: '会话长时间未活动时，自动发送告别提示语并将对话标记为“已解决”',
    rule: {
      name: '超时未回复自动结束会话',
      description: '长时间未收到客户回复时，发送结束语并自动标记已解决',
      event_name: 'conversation_updated',
      conditions: [
        {
          attribute_key: 'status',
          filter_operator: 'equal_to',
          values: [{ id: 'open', name: 'Open' }],
          query_operator: 'and',
          custom_attribute_type: '',
        },
      ],
      actions: [
        {
          action_name: 'send_message',
          action_params: [
            '由于长时间未收到您的进一步回复，本次会话已自动结束。如需再次咨询，随时向我们发送新消息即可，祝您生活愉快！',
          ],
        },
        {
          action_name: 'resolve_conversation',
          action_params: [],
        },
      ],
    },
  },
];
