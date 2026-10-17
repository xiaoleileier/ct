# frozen_string_literal: true

class Webhooks::TelegramRelayController < ActionController::API
  def process_payload
    msg = params[:message] || params[:edited_message]
    return head :ok if msg.blank?
    return head :ok if msg.dig(:from, :is_bot)

    chat_id = msg.dig(:chat, :id).to_s
    thread_id = msg[:message_thread_id]
    return head :ok if thread_id.blank?

    conversation = Conversation.where("additional_attributes ->> 'telegram_topic_id' = ?", thread_id.to_s).last
    return head :ok if conversation.blank?

    account = conversation.account
    return head :ok unless Telegram::ForumRelayService.configured?(account)

    expected_group_id = Telegram::ForumRelayService.group_id(account).to_s
    return head :ok unless chat_id == expected_group_id

    # Sync forum topic closed / reopened actions from Telegram to Chatwoot
    if msg[:forum_topic_closed].present?
      conversation.resolved! unless conversation.resolved?
      return head :ok
    end

    if msg[:forum_topic_reopened].present?
      conversation.open! unless conversation.open?
      return head :ok
    end

    # Support /resolve, /close, /reopen commands inside topic
    text = (msg[:text] || msg[:caption]).to_s.strip
    if ['/resolve', '/close'].include?(text.downcase)
      conversation.resolved! unless conversation.resolved?
      Telegram::ForumRelayService.handle_conversation_status_change(conversation)
      return head :ok
    elsif ['/reopen', '/open'].include?(text.downcase)
      conversation.open! unless conversation.open?
      Telegram::ForumRelayService.handle_conversation_status_change(conversation)
      return head :ok
    end

    process_telegram_reply(conversation, msg)

    head :ok
  rescue StandardError => e
    Rails.logger.error "Telegram relay webhook error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    head :ok
  end

  def setup_webhook
    account = Account.find_by(id: params[:account_id]) if params[:account_id].present?
    bot_token = params[:bot_token].presence || Telegram::ForumRelayService.bot_token(account)
    return render json: { ok: false, error: '未配置 Telegram 机器人 Token' }, status: :unprocessable_entity if bot_token.blank?

    frontend_url = ENV.fetch('FRONTEND_URL', request.base_url)
    webhook_url = "#{frontend_url}/webhooks/telegram_relay"

    res = HTTParty.post("https://api.telegram.org/bot#{bot_token}/setWebhook", body: {
      url: webhook_url,
      allowed_updates: ['message', 'edited_message']
    })

    render json: {
      ok: res.parsed_response['ok'] == true,
      webhook_url: webhook_url,
      telegram_response: res.parsed_response
    }
  rescue StandardError => e
    render json: { ok: false, error: e.message }, status: :unprocessable_entity
  end

  def check_status
    account = Account.find_by(id: params[:account_id]) if params[:account_id].present?
    bot_token = params[:bot_token].presence || Telegram::ForumRelayService.bot_token(account)
    group_id = params[:group_id].presence || Telegram::ForumRelayService.group_id(account)
    return render json: { configured: false, ok: false, error: '尚未配置 Telegram 机器人 Token' } if bot_token.blank?

    bot_res = HTTParty.get("https://api.telegram.org/bot#{bot_token}/getMe")
    unless bot_res.parsed_response['ok']
      return render json: { configured: false, ok: false, error: "Bot Token 无效: #{bot_res.parsed_response['description']}" }
    end

    bot_info = bot_res.parsed_response['result']
    webhook_res = HTTParty.get("https://api.telegram.org/bot#{bot_token}/getWebhookInfo").parsed_response['result']

    group_check = {}
    if group_id.present?
      chat_res = HTTParty.get("https://api.telegram.org/bot#{bot_token}/getChat?chat_id=#{group_id}").parsed_response
      if chat_res['ok']
        chat = chat_res['result']
        member_url = "https://api.telegram.org/bot#{bot_token}/getChatMember?chat_id=#{group_id}&user_id=#{bot_info['id']}"
        member_res = HTTParty.get(member_url).parsed_response

        member = member_res['result'] if member_res['ok']
        status = member&.[]('status')

        group_check = {
          valid: true,
          title: chat['title'],
          type: chat['type'],
          is_forum: chat['is_forum'] == true,
          bot_is_admin: %w[administrator creator].include?(status),
          can_manage_topics: member&.[]('can_manage_topics') == true || status == 'creator'
        }
      else
        group_check = {
          valid: false,
          error: chat_res['description']
        }
      end
    end

    render json: {
      configured: true,
      ok: true,
      bot: bot_info,
      webhook: webhook_res,
      group_id: group_id,
      group: group_check
    }
  rescue StandardError => e
    render json: { configured: false, ok: false, error: e.message }
  end

  private

  def process_telegram_reply(conversation, msg)
    text = msg[:text] || msg[:caption]
    photo_array = msg[:photo]
    document = msg[:document]
    sticker = msg[:sticker]
    voice = msg[:voice]
    audio = msg[:audio]
    video = msg[:video]
    location = msg[:location]

    if sticker.present? && text.blank?
      text = sticker[:emoji].presence || '[贴纸表情]'
    elsif location.present? && text.blank?
      text = "📍 位置: 纬度 #{location[:latitude]}, 经度 #{location[:longitude]}"
    end

    agent = conversation.assignee || conversation.account.users.first

    default_content = if photo_array.present?
                        '[图片]'
                      elsif voice.present? || audio.present?
                        '[语音消息]'
                      elsif video.present?
                        '[视频]'
                      elsif document.present?
                        '[附件]'
                      end

    message = conversation.messages.build(
      account: conversation.account,
      inbox: conversation.inbox,
      message_type: :outgoing,
      content: text.presence || default_content,
      sender: agent,
      source_id: "telegram_#{msg[:message_id]}"
    )

    attach_photo(message, photo_array) if photo_array.present?
    attach_document(message, document) if document.present?
    attach_voice(message, voice || audio) if (voice || audio).present?
    attach_video(message, video) if video.present?

    message.save!
  end

  def attach_photo(message, photo_array)
    best_photo = photo_array.last
    return unless best_photo

    download_and_attach(message, best_photo[:file_id], :image)
  end

  def attach_document(message, document)
    return unless document

    download_and_attach(message, document[:file_id], :file, document[:file_name])
  end

  def attach_voice(message, voice_obj)
    return unless voice_obj

    download_and_attach(message, voice_obj[:file_id], :audio, "voice_#{voice_obj[:file_id]}.ogg")
  end

  def attach_video(message, video_obj)
    return unless video_obj

    download_and_attach(message, video_obj[:file_id], :video, video_obj[:file_name] || "video_#{video_obj[:file_id]}.mp4")
  end

  def download_and_attach(message, file_id, file_type, custom_filename = nil)
    bot_token = Telegram::ForumRelayService.bot_token(message.account)
    file_info = HTTParty.get("https://api.telegram.org/bot#{bot_token}/getFile?file_id=#{file_id}")
    return unless file_info.success? && file_info.parsed_response['ok']

    file_path = file_info.parsed_response.dig('result', 'file_path')
    return if file_path.blank?

    download_url = "https://api.telegram.org/file/bot#{bot_token}/#{file_path}"
    downloaded_file = Down.download(download_url)

    filename = custom_filename || downloaded_file.original_filename || "telegram_#{file_id}"
    content_type = downloaded_file.content_type || 'application/octet-stream'

    message.attachments.new(
      account_id: message.account_id,
      file_type: file_type,
      file: {
        io: downloaded_file,
        filename: filename,
        content_type: content_type
      }
    )
  rescue StandardError => e
    Rails.logger.warn "Failed to download and attach file from Telegram: #{e.message}"
  end
end
