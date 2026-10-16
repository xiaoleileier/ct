# frozen_string_literal: true

class Telegram::ForumRelayService
  pattr_initialize [:message!]

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

    topic_id = conversation.additional_attributes['telegram_topic_id']

    if topic_id.blank?
      topic_id = create_topic!
      return if topic_id.blank?

      send_initial_profile_card(topic_id)
    end

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
      HTTParty.post(api_url('sendMessage', account), body: {
        chat_id: gid,
        message_thread_id: topic_id,
        text: '✅ <b>该会话已被客服在后台解决 (Resolved)</b>',
        parse_mode: 'HTML'
      })
    elsif conversation.open?
      HTTParty.post(api_url('reopenForumTopic', account), body: {
        chat_id: gid,
        message_thread_id: topic_id
      })
      HTTParty.post(api_url('sendMessage', account), body: {
        chat_id: gid,
        message_thread_id: topic_id,
        text: '🔄 <b>该会话已被客服在后台重新打开 (Reopened)</b>',
        parse_mode: 'HTML'
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

  private

  delegate :conversation, to: :message
  delegate :contact, :account, :inbox, to: :conversation

  def create_topic!
    topic_name = self.class.build_topic_name(conversation)
    response = HTTParty.post(self.class.api_url('createForumTopic', account), body: {
      chat_id: self.class.group_id(account),
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
    frontend_url = ENV['FRONTEND_URL'].presence || 'http://localhost:3000'
    conv_url = "#{frontend_url}/app/accounts/#{account.id}/conversations/#{conversation.display_id}"

    location = [contact.additional_attributes&.dig('city'), contact.additional_attributes&.dig('country_name')].compact.join(', ')
    location_line = location.present? ? "🌍 <b>地理位置</b>: #{CGI.escapeHTML(location)}\n" : ''

    card_text = <<~HTML
      🎉 <b>新客户咨询发起 (会话 ##{conversation.display_id})</b>
      ━━━━━━━━━━━━━━━━━━━━
      👤 <b>客户姓名</b>: #{CGI.escapeHTML(contact.name.presence || '新访客')}
      📱 <b>联系电话</b>: #{contact.phone_number.presence || '未留'}
      📧 <b>电子邮箱</b>: #{contact.email.presence || '未留'}
      #{location_line}🌐 <b>来源页面</b>: #{CGI.escapeHTML(conversation.additional_attributes['referer'].to_s.presence || '直接访问')}
      📥 <b>接入渠道</b>: #{CGI.escapeHTML(inbox.name)}
      🔗 <a href="#{conv_url}">点击在客服后台打开此会话</a>
      ━━━━━━━━━━━━━━━━━━━━
      💡 <i>提示: 在此话题内直接回复文字、表情或图片，将直接发送给网站访客！</i>
    HTML

    HTTParty.post(self.class.api_url('sendMessage', account), body: {
      chat_id: self.class.group_id(account),
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
                      sender_name = message.sender&.name.presence || '客服'
                      "🧑‍💼 <b>#{CGI.escapeHTML(sender_name)} [后台]</b>:\n"
                    end

    if message.content.present?
      text = "#{sender_prefix}#{CGI.escapeHTML(message.content)}"
      HTTParty.post(self.class.api_url('sendMessage', account), body: {
        chat_id: self.class.group_id(account),
        message_thread_id: topic_id,
        text: text,
        parse_mode: 'HTML'
      })
    end

    relay_attachments(topic_id) if message.attachments.present?
  end

  def relay_attachments(topic_id)
    message.attachments.each do |att|
      if att.image?
        send_telegram_file('sendPhoto', :photo, att, topic_id)
      elsif att.audio?
        send_telegram_file('sendVoice', :voice, att, topic_id)
      elsif att.video?
        send_telegram_file('sendVideo', :video, att, topic_id)
      else
        send_telegram_file('sendDocument', :document, att, topic_id)
      end
    end
  end

  def send_telegram_file(action, field, att, topic_id)
    gid = self.class.group_id(account)
    url = self.class.api_url(action, account)

    if att.file.attached?
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
  rescue StandardError => e
    Rails.logger.warn "Failed to send #{field} to Telegram: #{e.message}"
  end
end
