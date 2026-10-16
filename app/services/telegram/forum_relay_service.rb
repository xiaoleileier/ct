# frozen_string_literal: true

class Telegram::ForumRelayService
  pattr_initialize [:message!]

  def self.configured?
    ENV['TELEGRAM_RELAY_BOT_TOKEN'].present? && ENV['TELEGRAM_RELAY_GROUP_ID'].present?
  end

  def self.bot_token
    ENV.fetch('TELEGRAM_RELAY_BOT_TOKEN', nil)
  end

  def self.group_id
    ENV.fetch('TELEGRAM_RELAY_GROUP_ID', nil)
  end

  def self.api_url(endpoint)
    "https://api.telegram.org/bot#{bot_token}/#{endpoint}"
  end

  def perform
    return unless self.class.configured?
    return if message.source_id&.start_with?('telegram_')
    return if message.private?

    topic_id = conversation.additional_attributes['telegram_topic_id']

    if topic_id.blank?
      topic_id = create_topic!
      return if topic_id.blank?

      send_initial_profile_card(topic_id)
    end

    relay_message(topic_id)
  end

  def self.handle_conversation_status_change(conversation)
    return unless configured?

    topic_id = conversation.additional_attributes['telegram_topic_id']
    return if topic_id.blank?

    if conversation.resolved?
      HTTParty.post(api_url('closeForumTopic'), body: {
        chat_id: group_id,
        message_thread_id: topic_id
      })
      HTTParty.post(api_url('sendMessage'), body: {
        chat_id: group_id,
        message_thread_id: topic_id,
        text: '✅ <b>该会话已被客服在后台解决 (Resolved)</b>',
        parse_mode: 'HTML'
      })
    elsif conversation.open?
      HTTParty.post(api_url('reopenForumTopic'), body: {
        chat_id: group_id,
        message_thread_id: topic_id
      })
    end
  rescue StandardError => e
    Rails.logger.warn "Telegram Forum Relay status change failed: #{e.message}"
  end

  def self.update_topic_title(conversation)
    return unless configured?

    topic_id = conversation.additional_attributes['telegram_topic_id']
    return if topic_id.blank?

    name = build_topic_name(conversation)
    HTTParty.post(api_url('editForumTopic'), body: {
      chat_id: group_id,
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

  private

  delegate :conversation, to: :message
  delegate :contact, :account, :inbox, to: :conversation

  def create_topic!
    topic_name = self.class.build_topic_name(conversation)
    response = HTTParty.post(self.class.api_url('createForumTopic'), body: {
      chat_id: self.class.group_id,
      name: topic_name
    })

    if response.success? && response.parsed_response['ok']
      topic_id = response.parsed_response.dig('result', 'message_thread_id')
      conversation.additional_attributes ||= {}
      conversation.additional_attributes['telegram_topic_id'] = topic_id
      conversation.save!
      topic_id
    else
      Rails.logger.error "Failed to create Telegram forum topic: #{response.body}"
      nil
    end
  end

  def send_initial_profile_card(topic_id)
    frontend_url = ENV.fetch('FRONTEND_URL', 'http://localhost:3000')
    conv_url = "#{frontend_url}/app/accounts/#{account.id}/conversations/#{conversation.display_id}"

    card_text = <<~HTML
      🎉 <b>新客户咨询发起 (会话 ##{conversation.display_id})</b>
      ━━━━━━━━━━━━━━━━━━━━
      👤 <b>客户姓名</b>: #{CGI.escapeHTML(contact.name.presence || '新访客')}
      📱 <b>联系电话</b>: #{contact.phone_number.presence || '未留'}
      📧 <b>电子邮箱</b>: #{contact.email.presence || '未留'}
      🌐 <b>来源页面</b>: #{CGI.escapeHTML(conversation.additional_attributes['referer'].to_s.presence || '直接访问')}
      📥 <b>接入渠道</b>: #{CGI.escapeHTML(inbox.name)}
      🔗 <a href="#{conv_url}">点击在客服后台打开此会话</a>
      ━━━━━━━━━━━━━━━━━━━━
      💡 <i>提示: 在此话题内直接回复文字、表情或图片，将直接发送给网站访客！</i>
    HTML

    HTTParty.post(self.class.api_url('sendMessage'), body: {
      chat_id: self.class.group_id,
      message_thread_id: topic_id,
      text: card_text,
      parse_mode: 'HTML',
      disable_web_page_preview: true
    })
  end

  def relay_message(topic_id)
    sender_prefix = if message.incoming?
                      "💬 <b>客户</b>:\n"
                    else
                      "🧑‍💼 <b>客服 [后台]</b>:\n"
                    end

    if message.content.present?
      text = "#{sender_prefix}#{CGI.escapeHTML(message.content)}"
      HTTParty.post(self.class.api_url('sendMessage'), body: {
        chat_id: self.class.group_id,
        message_thread_id: topic_id,
        text: text,
        parse_mode: 'HTML'
      })
    end

    relay_attachments(topic_id) if message.attachments.present?
  end

  def relay_attachments(topic_id)
    message.attachments.each do |att|
      url = att.download_url
      next if url.blank?

      if att.image?
        HTTParty.post(self.class.api_url('sendPhoto'), body: {
          chat_id: self.class.group_id,
          message_thread_id: topic_id,
          photo: url
        })
      else
        HTTParty.post(self.class.api_url('sendDocument'), body: {
          chat_id: self.class.group_id,
          message_thread_id: topic_id,
          document: url
        })
      end
    rescue StandardError => e
      Rails.logger.warn "Failed to send attachment to Telegram: #{e.message}"
    end
  end
end
