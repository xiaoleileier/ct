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

    # Support /resolve, /close, /reopen, /info, /canned, /note, /tag, /help commands inside topic
    text = (msg[:text] || msg[:caption]).to_s.strip
    if text.start_with?('/')
      parts = text.split(/\s+/, 2)
      cmd = parts.first.to_s.downcase.sub(%r{^/}, '').sub(/@\w+$/, '')
      cmd_args = parts.second.to_s.strip

      case cmd
      when 'resolve', 'close', '解决'
        conversation.resolved! unless conversation.resolved?
        Telegram::ForumRelayService.handle_conversation_status_change(conversation)
        send_bot_topic_message(conversation, thread_id, "✅ <b>会话 ##{conversation.display_id} 已由客服标记为【已解决】</b>")
        return head :ok
      when 'reopen', 'open', '重开'
        conversation.open! unless conversation.open?
        Telegram::ForumRelayService.handle_conversation_status_change(conversation)
        send_bot_topic_message(conversation, thread_id, "🔄 <b>会话 ##{conversation.display_id} 已由客服重新打开</b>")
        return head :ok
      when 'info', 'user', 'profile', '用户信息'
        Telegram::ForumRelayService.new(conversation: conversation).send_initial_profile_card(thread_id)
        return head :ok
      when 'note', '备注'
        if cmd_args.present?
          agent = conversation.assignee || conversation.account.users.first
          conversation.messages.create!(
            account: conversation.account,
            inbox: conversation.inbox,
            message_type: :activity,
            private: true,
            content: cmd_args,
            sender: agent
          )
          send_bot_topic_message(conversation, thread_id, "📝 <b>内部备注已记录 (仅客服可见)</b>:\n#{CGI.escapeHTML(cmd_args)}")
        else
          send_bot_topic_message(conversation, thread_id, "⚠️ 请提供备注内容，例如: <code>/note 客户反馈香港02节点超时</code>")
        end
        return head :ok
      when 'tag', 'label', '标签'
        if cmd_args.present?
          labels = cmd_args.split(/[,，\s]+/).map(&:strip).reject(&:blank?)
          conversation.add_labels(labels)
          send_bot_topic_message(conversation, thread_id, "🏷️ <b>已添加会话标签</b>: #{CGI.escapeHTML(labels.join(', '))}")
        else
          send_bot_topic_message(conversation, thread_id, "⚠️ 请提供标签名，例如: <code>/tag 节点故障, 充值未到账</code>")
        end
        return head :ok
      when 'canned', 'quick', '快捷回复', '话术'
        canned_list = conversation.account.canned_responses.order(:short_code).limit(25)
        if canned_list.any?
          lines = canned_list.map do |cr|
            "• <code>/#{cr.short_code}</code> : #{CGI.escapeHTML(cr.content.truncate(45))}"
          end
          send_bot_topic_message(conversation, thread_id, "📋 <b>快捷预设话术列表</b> (直接发送 <code>/快捷码</code> 即可发给客户):\n\n#{lines.join("\n")}")
        else
          send_bot_topic_message(conversation, thread_id, "📋 暂无预设快捷话术，可在 Chatwoot 后台【设置 -> 快捷回复】中添加。")
        end
        return head :ok
      when 'help', '帮助'
        help_text = <<~HELP.strip
          💡 <b>Telegram 客服快捷指令指南</b>

          • <b>直接回复</b>: 发送文字/图片/动图/语音/文件，直接同步回复客户
          • <code>/resolve</code>: 解决并关闭当前会话
          • <code>/reopen</code>: 重新打开已关闭会话
          • <code>/info</code>: 重新调出客户画像与订阅信息卡片
          • <code>/canned</code>: 查看所有快捷预设话术列表
          • <code>/&lt;快捷码&gt;</code>: 直接发送预设话术给客户 (如 <code>/clash</code>)
          • <code>/note &lt;内容&gt;</code>: 添加客服内部私密备注 (客户不可见)
          • <code>/tag &lt;标签&gt;</code>: 为会话打标签 (如 <code>/tag 节点故障</code>)
          • <code>/help</code>: 查看本帮助指南
        HELP
        send_bot_topic_message(conversation, thread_id, help_text)
        return head :ok
      else
        canned = conversation.account.canned_responses.find_by('lower(short_code) = ?', cmd)
        if canned.present?
          agent = conversation.assignee || conversation.account.users.first
          conversation.messages.create!(
            account: conversation.account,
            inbox: conversation.inbox,
            message_type: :outgoing,
            content: canned.content,
            sender: agent,
            source_id: "telegram_canned_#{msg[:message_id]}"
          )
          send_bot_topic_message(conversation, thread_id, "🚀 <b>已发送快捷话术【#{canned.short_code}】给客户</b>:\n#{CGI.escapeHTML(canned.content)}")
          return head :ok
        end
      end
    end

    process_telegram_reply(conversation, msg)

    head :ok
  rescue StandardError => e
    Rails.logger.error "Telegram relay webhook error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    head :ok
  end

  def self.register_telegram_commands(bot_token)
    commands = [
      { command: 'resolve', description: '✅ 解决并关闭当前会话' },
      { command: 'info', description: '📊 刷新客户画像与订阅详情' },
      { command: 'reopen', description: '🔄 重新打开已解决会话' },
      { command: 'canned', description: '📋 查看快捷回复话术列表' },
      { command: 'note', description: '📝 内部私密备注: /note 内容' },
      { command: 'tag', description: '🏷️ 会话标签: /tag 节点故障' },
      { command: 'help', description: '💡 客服指令操作帮助指南' }
    ]

    HTTParty.post(
      "https://api.telegram.org/bot#{bot_token}/setMyCommands",
      headers: { 'Content-Type' => 'application/json' },
      body: { commands: commands }.to_json
    ).parsed_response
  rescue StandardError => e
    Rails.logger.warn "Failed to register telegram commands: #{e.message}"
    { 'ok' => false, 'error' => e.message }
  end

  def sync_commands
    account = Account.find_by(id: params[:account_id]) if params[:account_id].present?
    bot_token = params[:bot_token].presence || Telegram::ForumRelayService.bot_token(account)
    return render json: { ok: false, error: '未配置 Telegram 机器人 Token' }, status: :unprocessable_entity if bot_token.blank?

    res = self.class.register_telegram_commands(bot_token)
    render json: { ok: res['ok'] == true, telegram_response: res }
  rescue StandardError => e
    render json: { ok: false, error: e.message }, status: :unprocessable_entity
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

    # Auto register / command menu in Telegram
    self.class.register_telegram_commands(bot_token)

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

    # Fetch and ensure bot commands are registered
    commands_res = HTTParty.get("https://api.telegram.org/bot#{bot_token}/getMyCommands").parsed_response
    commands = commands_res['ok'] ? commands_res['result'] : []
    if commands.blank?
      self.class.register_telegram_commands(bot_token)
      commands_res = HTTParty.get("https://api.telegram.org/bot#{bot_token}/getMyCommands").parsed_response
      commands = commands_res['ok'] ? commands_res['result'] : []
    end

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
      commands: commands,
      group_id: group_id,
      group: group_check
    }
  rescue StandardError => e
    render json: { configured: false, ok: false, error: e.message }
  end

  private

  def send_bot_topic_message(conversation, thread_id, html_text)
    account = conversation.account
    bot_token = Telegram::ForumRelayService.bot_token(account)
    group_id = Telegram::ForumRelayService.group_id(account)
    return if bot_token.blank? || group_id.blank?

    HTTParty.post("https://api.telegram.org/bot#{bot_token}/sendMessage", body: {
      chat_id: group_id,
      message_thread_id: thread_id,
      text: html_text,
      parse_mode: 'HTML'
    })
  rescue StandardError => e
    Rails.logger.warn "Failed to send bot topic message: #{e.message}"
  end

  def process_telegram_reply(conversation, msg)
    text = msg[:text] || msg[:caption]
    photo_array = msg[:photo]
    animation = msg[:animation]
    # Telegram sends both animation and document for GIF messages; avoid duplicate
    document = msg[:document] unless animation.present?
    sticker = msg[:sticker]
    voice = msg[:voice]
    audio = msg[:audio]
    video = msg[:video]
    location = msg[:location]

    if location.present? && text.blank?
      text = "📍 位置: 纬度 #{location[:latitude]}, 经度 #{location[:longitude]}"
    end

    agent = conversation.assignee || conversation.account.users.first

    default_content = if photo_array.present?
                        '[图片]'
                      elsif animation.present?
                        '[动图]'
                      elsif sticker.present?
                        sticker[:emoji].presence || '[贴纸表情]'
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
    attach_animation(message, animation) if animation.present?
    attach_sticker(message, sticker) if sticker.present?
    attach_document(message, document) if document.present?
    attach_voice(message, voice || audio) if (voice || audio).present?
    attach_video(message, video) if video.present?

    # If visual media (photo, animation, video, or sticker) was attached and no custom text was typed,
    # clear content so it renders cleanly as visual media without a redundant text bubble
    if message.attachments.any? { |att| att.image? || att.video? } && msg[:text].blank? && msg[:caption].blank?
      message.content = nil
    end

    message.save!
  end

  def attach_photo(message, photo_array)
    best_photo = photo_array.last
    return unless best_photo

    download_and_attach(message, best_photo[:file_id], :image, "photo_#{Time.current.to_i}.jpg")
  end

  def attach_animation(message, animation)
    return unless animation

    file_id = animation[:file_id]
    mime_type = animation[:mime_type].to_s.downcase
    # Telegram animations are either video/mp4 (H.264 animation without sound) or image/gif
    file_type = (mime_type == 'image/gif' || animation[:file_name].to_s.downcase.end_with?('.gif')) ? :image : :video
    ext = file_type == :image ? 'gif' : 'mp4'
    custom_filename = animation[:file_name].presence || "animation_#{Time.current.to_i}.#{ext}"

    download_and_attach(message, file_id, file_type, custom_filename)
  end

  def attach_sticker(message, sticker)
    return unless sticker

    # Telegram stickers provide thumbnail (or thumb in older API) which is always a valid webp/jpg image.
    # For static webp stickers, file_id itself is a valid webp image.
    best_file_id = if sticker[:is_animated] || sticker[:is_video]
                     sticker.dig(:thumbnail, :file_id) || sticker.dig(:thumb, :file_id)
                   else
                     sticker[:file_id] || sticker.dig(:thumbnail, :file_id) || sticker.dig(:thumb, :file_id)
                   end

    return unless best_file_id

    download_and_attach(message, best_file_id, :image, "sticker_#{Time.current.to_i}.webp")
  end

  def attach_document(message, document)
    return unless document

    file_id = document[:file_id]
    mime_type = document[:mime_type].to_s.downcase
    file_name = document[:file_name].to_s

    # Smart detect file type from mime_type or file extension
    file_type = if mime_type.start_with?('image/') || file_name.match?(/\.(jpe?g|png|gif|webp|bmp|svg)$/i)
                  :image
                elsif mime_type.start_with?('video/') || file_name.match?(/\.(mp4|mov|avi|mkv|webm)$/i)
                  :video
                elsif mime_type.start_with?('audio/') || file_name.match?(/\.(mp3|ogg|wav|m4a|aac)$/i)
                  :audio
                else
                  :file
                end

    custom_filename = document[:file_name].presence || "file_#{Time.current.to_i}"
    download_and_attach(message, file_id, file_type, custom_filename)
  end

  def attach_voice(message, voice_obj)
    return unless voice_obj

    download_and_attach(message, voice_obj[:file_id], :audio, "voice_#{Time.current.to_i}.ogg")
  end

  def attach_video(message, video_obj)
    return unless video_obj

    download_and_attach(message, video_obj[:file_id], :video, video_obj[:file_name] || "video_#{Time.current.to_i}.mp4")
  end

  def download_and_attach(message, file_id, file_type, custom_filename = nil)
    bot_token = Telegram::ForumRelayService.bot_token(message.account)
    file_info = HTTParty.get("https://api.telegram.org/bot#{bot_token}/getFile?file_id=#{file_id}")
    return unless file_info.success? && file_info.parsed_response['ok']

    file_path = file_info.parsed_response.dig('result', 'file_path')
    return if file_path.blank?

    download_url = "https://api.telegram.org/file/bot#{bot_token}/#{file_path}"
    downloaded_file = Down.download(download_url)

    path_filename = File.basename(file_path) if file_path.present?
    filename = custom_filename || (path_filename.present? && !path_filename.start_with?('file_') ? path_filename : nil) || downloaded_file.original_filename || "attachment_#{Time.current.to_i}"
    content_type = downloaded_file.content_type || 'application/octet-stream'
    content_type = 'image/webp' if filename.ends_with?('.webp') && content_type == 'application/octet-stream'
    content_type = 'image/gif' if filename.ends_with?('.gif') && content_type == 'application/octet-stream'
    content_type = 'video/mp4' if filename.ends_with?('.mp4') && content_type == 'application/octet-stream'

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
