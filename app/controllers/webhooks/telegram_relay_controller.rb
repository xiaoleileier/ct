# frozen_string_literal: true

class Webhooks::TelegramRelayController < ActionController::API
  def process_payload
    return head :ok unless Telegram::ForumRelayService.configured?

    msg = params[:message] || params[:edited_message]
    return head :ok if msg.blank?
    return head :ok if msg.dig(:from, :is_bot)

    chat_id = msg.dig(:chat, :id).to_s
    expected_group_id = Telegram::ForumRelayService.group_id.to_s
    return head :ok unless chat_id == expected_group_id

    thread_id = msg[:message_thread_id]
    return head :ok if thread_id.blank?

    conversation = Conversation.where("additional_attributes ->> 'telegram_topic_id' = ?", thread_id.to_s).last
    return head :ok if conversation.blank?

    process_telegram_reply(conversation, msg)

    head :ok
  rescue StandardError => e
    Rails.logger.error "Telegram relay webhook error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    head :ok
  end

  def setup_webhook
    return render json: { error: 'Not configured' }, status: :unprocessable_entity unless Telegram::ForumRelayService.configured?

    bot_token = Telegram::ForumRelayService.bot_token
    frontend_url = ENV.fetch('FRONTEND_URL', nil)
    webhook_url = "#{frontend_url}/webhooks/telegram_relay"

    res = HTTParty.post("https://api.telegram.org/bot#{bot_token}/setWebhook", body: {
      url: webhook_url,
      allowed_updates: ['message', 'edited_message']
    })

    render json: {
      webhook_url: webhook_url,
      telegram_response: res.parsed_response
    }
  end

  private

  def process_telegram_reply(conversation, msg)
    text = msg[:text] || msg[:caption]
    photo_array = msg[:photo]
    document = msg[:document]
    sticker = msg[:sticker]

    if sticker.present? && text.blank?
      text = sticker[:emoji] || '[贴纸表情]'
    end

    agent = conversation.account.users.first

    message = conversation.messages.build(
      account: conversation.account,
      inbox: conversation.inbox,
      message_type: :outgoing,
      content: text.presence || (photo_array.present? ? '[图片]' : '[附件]'),
      sender: agent,
      source_id: "telegram_#{msg[:message_id]}"
    )

    attach_photo(message, photo_array) if photo_array.present?
    attach_document(message, document) if document.present?

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

  def download_and_attach(message, file_id, file_type, custom_filename = nil)
    bot_token = Telegram::ForumRelayService.bot_token
    file_info = HTTParty.get("https://api.telegram.org/bot#{bot_token}/getFile?file_id=#{file_id}")
    return unless file_info.success? && file_info.parsed_response['ok']

    file_path = file_info.parsed_response.dig('result', 'file_path')
    return if file_path.blank?

    download_url = "https://api.telegram.org/file/bot#{bot_token}/#{file_path}"
    downloaded_file = Down.download(download_url)

    filename = custom_filename || downloaded_file.original_filename || "telegram_#{file_id}.jpg"
    content_type = downloaded_file.content_type || 'image/jpeg'

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
