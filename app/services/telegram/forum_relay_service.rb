# frozen_string_literal: true

class Telegram::ForumRelayService
  def initialize(message: nil, conversation: nil)
    @message = message
    @conversation = conversation || message&.conversation
  end

  attr_reader :message, :conversation

  def self.configured?(account = nil)
    bot_token(account).present? && group_id(account).present? && enabled?(account)
  end

  def self.enabled?(account = nil)
    return true if account.blank? || account.settings.blank? || !account.settings.key?('telegram_relay_enabled')

    ActiveModel::Type::Boolean.new.cast(account.settings['telegram_relay_enabled'])
  end

  def self.bot_token(account = nil)
    token = account&.settings&.dig('telegram_relay_bot_token')
    token.presence || ENV.fetch('TELEGRAM_RELAY_BOT_TOKEN', nil)
  end

  def self.group_id(account = nil)
    gid = account&.settings&.dig('telegram_relay_group_id')
    gid.presence || ENV.fetch('TELEGRAM_RELAY_GROUP_ID', nil)
  end

  def self.api_url(endpoint, account = nil)
    "https://api.telegram.org/bot#{bot_token(account)}/#{endpoint}"
  end

  def perform
    return unless self.class.configured?(account)
    return if message.source_id&.start_with?('telegram_')
    return if message.private?
    return if message.activity?
    return if message.input_csat?

    topic_id = ensure_topic_id!
    return if topic_id.blank?

    relay_message(topic_id)
  end

  def self.handle_conversation_status_change(conversation)
    account = conversation.account
    return unless configured?(account)

    topic_id = conversation.additional_attributes['telegram_topic_id']
    return if topic_id.blank?

    gid = group_id(account)

    if conversation.resolved?
      HTTParty.post(api_url('closeForumTopic', account), body: {
        chat_id: gid,
        message_thread_id: topic_id
      })
    elsif conversation.open?
      HTTParty.post(api_url('reopenForumTopic', account), body: {
        chat_id: gid,
        message_thread_id: topic_id
      })
    end
  rescue StandardError => e
    Rails.logger.warn "Telegram Forum Relay status change failed: #{e.message}"
  end

  def self.update_topic_title(conversation)
    account = conversation.account
    return unless configured?(account)

    topic_id = conversation.additional_attributes['telegram_topic_id']
    return if topic_id.blank?

    name = build_topic_name(conversation)
    HTTParty.post(api_url('editForumTopic', account), body: {
      chat_id: group_id(account),
      message_thread_id: topic_id,
      name: name
    })
  rescue StandardError => e
    Rails.logger.warn "Telegram Forum Relay update title failed: #{e.message}"
  end

  def self.build_topic_name(conv)
    c = conv.contact
    name_part = c.name.presence || '访客'
    phone_part = c.phone_number.present? ? " 📱#{c.phone_number}" : ''
    "💬 ##{conv.display_id} - #{name_part}#{phone_part}".truncate(120)
  end

  def self.delete_telegram_message(message)
    account = message.account
    return unless configured?(account)

    gid = group_id(account)
    tg_msg_id = message.additional_attributes&.[]('telegram_message_id') ||
                (message.source_id.to_s.start_with?('telegram_') ? message.source_id.sub(/^telegram_/, '') : nil)
    return if tg_msg_id.blank?

    HTTParty.post(api_url('deleteMessage', account), body: {
      chat_id: gid,
      message_id: tg_msg_id
    })
  rescue StandardError => e
    Rails.logger.warn "Failed to delete message on Telegram: #{e.message}"
  end

  private

  delegate :conversation, to: :message
  delegate :contact, :account, :inbox, to: :conversation

  def ensure_topic_id!
    conversation.reload
    existing_id = conversation.additional_attributes&.[]('telegram_topic_id')
    return existing_id if existing_id.present?

    newly_created = false
    topic_id = conversation.with_lock do
      conversation.reload
      current_id = conversation.additional_attributes&.[]('telegram_topic_id')
      if current_id.present?
        current_id
      else
        created_id = create_topic_on_telegram!
        if created_id.present?
          newly_created = true
          attrs = (conversation.additional_attributes || {}).merge('telegram_topic_id' => created_id)
          conversation.update_column(:additional_attributes, attrs)
        end
        created_id
      end
    end

    send_initial_profile_card(topic_id) if newly_created && topic_id.present?

    topic_id
  end

  def create_topic_on_telegram!
    topic_name = self.class.build_topic_name(conversation)
    response = HTTParty.post(self.class.api_url('createForumTopic', account), body: {
      chat_id: self.class.group_id(account),
      name: topic_name
    })

    if response.success? && response.parsed_response['ok']
      response.parsed_response.dig('result', 'message_thread_id')
    else
      Rails.logger.error "Failed to create Telegram forum topic: #{response.body}"
      nil
    end
  end

  def build_profile_card_text(conv_url = nil)
    contact.reload rescue nil
    conversation.reload rescue nil

    frontend_url = ENV['FRONTEND_URL'].presence || 'http://localhost:3000'
    url = conv_url || "#{frontend_url}/app/accounts/#{account.id}/conversations/#{conversation.display_id}"

    # Smart email detection
    email = contact.email.presence ||
            (contact.name.to_s.match?(URI::MailTo::EMAIL_REGEXP) ? contact.name : nil) ||
            (contact.identifier.to_s.match?(URI::MailTo::EMAIL_REGEXP) ? contact.identifier : nil) ||
            (contact.custom_attributes&.dig('user_id').to_s.presence if contact.custom_attributes&.dig('user_id').to_s.match?(URI::MailTo::EMAIL_REGEXP))

    contact.update(email: email) if contact.email.blank? && email.present? rescue nil

    location = [contact.additional_attributes&.dig('city'), contact.additional_attributes&.dig('country_name')].compact.join(', ')
    location_line = location.present? ? "🌍 <b>地理位置</b>: #{CGI.escapeHTML(location)}\n" : ''

    attr_lines = format_contact_attributes(email)
    attr_section = attr_lines.present? ? "#{attr_lines.join("\n")}\n" : ''

    assignee_name = conversation.assignee&.name || '未指派'
    labels = conversation.label_list
    labels_line = labels.any? ? "🏷️ <b>会话标签</b>: #{CGI.escapeHTML(labels.join(', '))}\n" : ''

    status_str = case conversation.status
                 when 'open' then '🟢 处理中'
                 when 'resolved' then '✅ 已解决'
                 when 'pending' then '⏳ 待处理'
                 when 'snoozed' then '💤 已暂停'
                 else conversation.status
                 end

    <<~HTML.strip
      🎉 <b>客户画像与会话详情 (会话 ##{conversation.display_id})</b>
      ━━━━━━━━━━━━━━━━━━━━
      👤 <b>客户姓名</b>: #{CGI.escapeHTML(contact.name.presence || '新访客')}
      📧 <b>电子邮箱</b>: #{CGI.escapeHTML(email.presence || '未留')}
      📱 <b>联系电话</b>: #{contact.phone_number.presence || '未留'}
      #{attr_section}#{location_line}🌐 <b>来源页面</b>: #{CGI.escapeHTML(conversation.additional_attributes['referer'].to_s.presence || '直接访问')}
      📥 <b>接入渠道</b>: #{CGI.escapeHTML(inbox.name)}
      📌 <b>会话状态</b>: #{status_str} | <b>责任客服</b>: #{CGI.escapeHTML(assignee_name)}
      #{labels_line}🔗 <a href="#{url}">点击在客服后台打开此会话</a>
      ━━━━━━━━━━━━━━━━━━━━
      💡 <i>提示: 点击下方快捷按钮操作，或直接回复消息。发送 <code>/help</code> 查看全部指令。</i>
    HTML
  end

  def build_profile_card_buttons(conv_url = nil)
    frontend_url = ENV['FRONTEND_URL'].presence || 'http://localhost:3000'
    url = conv_url || "#{frontend_url}/app/accounts/#{account.id}/conversations/#{conversation.display_id}"

    {
      inline_keyboard: [
        [
          { text: '📊 刷新数据', callback_data: "info:#{conversation.id}" },
          { text: '✅ 解决并关闭', callback_data: "resolve:#{conversation.id}" }
        ],
        [
          { text: '🏷️ 标记已留资', callback_data: "lead:#{conversation.id}" },
          { text: '🚫 屏蔽/拉黑', callback_data: "block:#{conversation.id}" }
        ],
        [
          { text: '🔗 打开客服后台', url: url }
        ]
      ]
    }
  end

  def send_initial_profile_card(topic_id)
    card_text = build_profile_card_text
    buttons = build_profile_card_buttons

    res = HTTParty.post(self.class.api_url('sendMessage', account), body: {
      chat_id: self.class.group_id(account),
      message_thread_id: topic_id,
      text: card_text,
      parse_mode: 'HTML',
      disable_web_page_preview: true,
      reply_markup: buttons.to_json
    })

    if res.success? && res.parsed_response['ok']
      card_msg_id = res.parsed_response.dig('result', 'message_id')
      attrs = (conversation.additional_attributes || {}).merge('telegram_card_message_id' => card_msg_id)
      conversation.update_column(:additional_attributes, attrs)
    end
  end

  def format_contact_attributes(email)
    lines = []
    ca = contact.custom_attributes || {}

    # User ID / Identifier (if distinct from email and name)
    uid = contact.identifier.presence || ca['user_id'].presence
    lines << "🆔 <b>用户 ID</b>: #{CGI.escapeHTML(uid.to_s)}" if uid.present? && uid != email && uid != contact.name

    # 1. Plan / Subscription
    lines << "💎 <b>当前套餐</b>: #{CGI.escapeHTML(ca['plan'].to_s)}" if ca['plan'].present?

    # 2. Balance / Money
    lines << "💰 <b>账户余额</b>: #{CGI.escapeHTML(ca['balance'].to_s)}" if ca['balance'].present?

    # 3. Traffic usage (formatted: used / total (remaining, percent))
    if ca['used_traffic'].present? || ca['total_traffic'].present?
      traffic_str = [ca['used_traffic'], ca['total_traffic']].compact.join(' / ')
      extra_traffic = []
      extra_traffic << "剩余 #{ca['remaining_traffic']}" if ca['remaining_traffic'].present?
      extra_traffic << "#{ca['traffic_percent']}%" if ca['traffic_percent'].present?
      traffic_str += " (#{extra_traffic.join(', ')})" if extra_traffic.present?
      lines << "📊 <b>流量使用</b>: #{CGI.escapeHTML(traffic_str)}"
    end

    # 4. Expiration date
    lines << "⏳ <b>到期时间</b>: #{CGI.escapeHTML(ca['expire_time'].to_s)}" if ca['expire_time'].present?

    # 5. Account status
    lines << "🟢 <b>账户状态</b>: #{CGI.escapeHTML(ca['account_status'].to_s)}" if ca['account_status'].present?

    # 6. Site / Airport name
    lines << "🏢 <b>所属站点</b>: #{CGI.escapeHTML(ca['site_name'].to_s)}" if ca['site_name'].present?

    # 7. Device / Platform
    device_info = [ca['device_platform'], ca['app_version'] || ca['device_name']].compact.join(' / ')
    lines << "💻 <b>设备系统</b>: #{CGI.escapeHTML(device_info)}" if device_info.present?

    # 8. Registration date
    lines << "📅 <b>注册时间</b>: #{CGI.escapeHTML(ca['registered_at'].to_s)}" if ca['registered_at'].present?

    # 9. Other custom attributes defined on the account
    known_keys = %w[
      plan balance used_traffic total_traffic remaining_traffic traffic_percent
      expire_time account_status site_name device_platform device_name
      app_version registered_at user_id last_sync_at app_channel
    ]
    definitions = account.custom_attribute_definitions.where(attribute_model: :contact_attribute).index_by(&:attribute_key)

    ca.each do |k, v|
      next if known_keys.include?(k) || v.blank?

      label = definitions[k]&.attribute_display_name || k.to_s.humanize
      lines << "🏷️ <b>#{CGI.escapeHTML(label)}</b>: #{CGI.escapeHTML(v.to_s)}"
    end

    lines
  end

  def relay_message(topic_id)
    sender_prefix = if message.incoming?
                      "💬 <b>客户</b>:\n"
                    else
                      sender_name = message.sender&.name.presence || '客服'
                      "🧑‍💼 <b>#{CGI.escapeHTML(sender_name)} [后台]</b>:\n"
                    end

    if message.content.present?
      text = "#{sender_prefix}#{CGI.escapeHTML(message.content)}".truncate(4000, omission: '... (消息过长已截断)')
      res = HTTParty.post(self.class.api_url('sendMessage', account), body: {
        chat_id: self.class.group_id(account),
        message_thread_id: topic_id,
        text: text,
        parse_mode: 'HTML'
      })

      if res.success? && res.parsed_response['ok']
        tg_id = res.parsed_response.dig('result', 'message_id')
        attrs = (message.additional_attributes || {}).merge('telegram_message_id' => tg_id)
        message.update_column(:additional_attributes, attrs)
      end

      # Auto-heal: If topic was deleted or closed in Telegram, recreate and re-send
      if res.parsed_response.is_a?(Hash) && res.parsed_response['error_code'] == 400 &&
         res.parsed_response['description']&.include?('message thread not found')
        Rails.logger.warn "Telegram topic #{topic_id} not found, recreating forum topic..."
        new_topic_id = conversation.with_lock do
          conversation.reload
          current_id = conversation.additional_attributes&.[]('telegram_topic_id')
          if current_id.present? && current_id != topic_id
            current_id
          else
            created_id = create_topic_on_telegram!
            if created_id.present?
              attrs = (conversation.additional_attributes || {}).merge('telegram_topic_id' => created_id)
              conversation.update_column(:additional_attributes, attrs)
              send_initial_profile_card(created_id)
            end
            created_id
          end
        end

        if new_topic_id.present?
          HTTParty.post(self.class.api_url('sendMessage', account), body: {
            chat_id: self.class.group_id(account),
            message_thread_id: new_topic_id,
            text: text,
            parse_mode: 'HTML'
          })
          topic_id = new_topic_id
        end
      end
    end

    relay_attachments(topic_id) if message.attachments.present?
  end

  def relay_attachments(topic_id)
    message.attachments.each do |att|
      if animation?(att)
        send_telegram_file('sendAnimation', :animation, att, topic_id)
      elsif att.image?
        send_telegram_file('sendPhoto', :photo, att, topic_id)
      elsif att.audio?
        send_telegram_file('sendAudio', :audio, att, topic_id)
      elsif att.video?
        send_telegram_file('sendVideo', :video, att, topic_id)
      else
        send_telegram_file('sendDocument', :document, att, topic_id)
      end
    end
  end

  def animation?(att)
    content_type = (att.file.attached? ? att.file.content_type : '').to_s.downcase
    filename = (att.file.attached? ? att.file.filename.to_s : att.fallback_title.to_s).downcase
    url = att.download_url.to_s.downcase
    content_type == 'image/gif' ||
      filename.end_with?('.gif') ||
      filename.include?('animation') ||
      url.end_with?('.gif') ||
      url.include?('animation')
  end

  def send_telegram_file(action, field, att, topic_id)
    gid = self.class.group_id(account)
    url = self.class.api_url(action, account)

    res = if att.file.attached?
            att.file.open do |tempfile|
              HTTParty.post(url, body: {
                chat_id: gid,
                message_thread_id: topic_id,
                field => File.open(tempfile.path)
              })
            end
          elsif att.download_url.present?
            HTTParty.post(url, body: {
              chat_id: gid,
              message_thread_id: topic_id,
              field => att.download_url
            })
          end

    if res&.success? && res.parsed_response['ok']
      tg_id = res.parsed_response.dig('result', 'message_id')
      attrs = (message.additional_attributes || {}).merge('telegram_message_id' => tg_id)
      message.update_column(:additional_attributes, attrs)
    end
  rescue StandardError => e
    Rails.logger.warn "Failed to send #{field} to Telegram: #{e.message}"
  end
end
