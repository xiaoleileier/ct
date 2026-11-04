# frozen_string_literal: true

class Webhooks::TelegramRelayController < ActionController::API
  def process_payload
    if params[:callback_query].present?
      handle_callback_query(params[:callback_query])
      return head :ok
    end

    if params[:edited_message].present?
      handle_edited_message(params[:edited_message])
      return head :ok
    end

    msg = params[:message]
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

    text = (msg[:text] || msg[:caption]).to_s.strip
    if text.start_with?('/')
      handled = handle_telegram_command(conversation, thread_id, msg, text)
      return head :ok if handled
    end

    process_telegram_reply(conversation, msg)

    head :ok
  rescue StandardError => e
    Rails.logger.error "Telegram relay webhook error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    head :ok
  end

  def handle_callback_query(cq)
    cq_id = cq[:id]
    data = cq[:data].to_s
    from = cq[:from]
    msg = cq[:message]
    chat_id = msg.dig(:chat, :id)
    msg_id = msg[:message_id]
    thread_id = msg[:message_thread_id]

    action, conv_id = data.split(':', 2)
    conversation = Conversation.find_by(id: conv_id) if conv_id.present?
    conversation ||= Conversation.where("additional_attributes ->> 'telegram_topic_id' = ?", thread_id.to_s).last

    account = conversation&.account
    return answer_callback(cq_id, '⚠️ 未找到对应会话', account: account, alert: true) if conversation.blank? || account.blank?

    case action
    when 'info'
      service = Telegram::ForumRelayService.new(conversation: conversation)
      new_text = service.build_profile_card_text
      buttons = service.build_profile_card_buttons

      HTTParty.post(Telegram::ForumRelayService.api_url('editMessageText', account), body: {
        chat_id: chat_id,
        message_id: msg_id,
        text: new_text,
        parse_mode: 'HTML',
        disable_web_page_preview: true,
        reply_markup: buttons.to_json
      }) rescue nil

      answer_callback(cq_id, '📊 客户画像与订阅数据已刷新！', account: account)
    when 'resolve'
      conversation.resolved! unless conversation.resolved?
      Telegram::ForumRelayService.handle_conversation_status_change(conversation)
      answer_callback(cq_id, '✅ 会话已标记解决，话题已关闭。', account: account)
    when 'lead'
      conversation.add_labels(['已留资'])
      Telegram::ForumRelayService.update_topic_title(conversation)
      answer_callback(cq_id, '🏷️ 已成功为会话添加【已留资】标签！', account: account)
    when 'block'
      conversation.add_labels(['已拉黑'])
      conversation.mute!
      Telegram::ForumRelayService.handle_conversation_status_change(conversation)
      answer_callback(cq_id, '🚫 该访客已拉黑屏蔽，会话已静音并解决！', account: account, alert: true)
    else
      answer_callback(cq_id, '未知指令', account: account)
    end
  rescue StandardError => e
    Rails.logger.error "Callback query error: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
    answer_callback(cq[:id], "操作失败: #{e.message}", alert: true) rescue nil
  end

  def answer_callback(cq_id, text, account: nil, alert: false)
    url = Telegram::ForumRelayService.api_url('answerCallbackQuery', account)
    HTTParty.post(url, body: {
      callback_query_id: cq_id,
      text: text,
      show_alert: alert
    })
  rescue StandardError => e
    Rails.logger.warn "Failed to answer callback query: #{e.message}"
  end

  def handle_edited_message(edited_msg)
    chat_id = edited_msg.dig(:chat, :id).to_s
    thread_id = edited_msg[:message_thread_id]
    return if thread_id.blank?

    conversation = Conversation.where("additional_attributes ->> 'telegram_topic_id' = ?", thread_id.to_s).last
    return if conversation.blank?

    tg_msg_id = edited_msg[:message_id]
    target_msg = conversation.messages.where(source_id: "telegram_#{tg_msg_id}").last
    return if target_msg.blank?

    new_text = (edited_msg[:text] || edited_msg[:caption]).to_s.strip
    return if new_text.blank?

    from = edited_msg[:from] || {}
    matched_agent = find_agent_for_telegram_sender(conversation.account, from)
    final_content = if matched_agent.present?
                      new_text
                    else
                      from_name = [from[:first_name], from[:last_name]].compact.join(' ').presence || from[:username] || 'TG客服'
                      "[TG客服: #{from_name}]\n#{new_text}"
                    end

    target_msg.update!(content: final_content)
  rescue StandardError => e
    Rails.logger.warn "Failed to handle edited message: #{e.message}"
  end

  def handle_telegram_command(conversation, thread_id, msg, text)
    parts = text.split(/\s+/, 2)
    cmd = parts.first.to_s.downcase.sub(%r{^/}, '').sub(/@\w+$/, '')
    cmd_args = parts.second.to_s.strip
    from = msg[:from] || {}
    account = conversation.account

    case cmd
    when 'resolve', 'close', '解决'
      conversation.resolved! unless conversation.resolved?
      Telegram::ForumRelayService.handle_conversation_status_change(conversation)
      true
    when 'reopen', 'open', '重开'
      conversation.open! unless conversation.open?
      Telegram::ForumRelayService.handle_conversation_status_change(conversation)
      true
    when 'info', 'user', 'profile', '用户信息'
      Telegram::ForumRelayService.new(conversation: conversation).send_initial_profile_card(thread_id)
      true
    when 'assign', '转接', '分配'
      handle_assign_command(conversation, thread_id, cmd_args)
      true
    when 'block', 'mute', '拉黑', '屏蔽'
      conversation.add_labels(['已拉黑'])
      conversation.mute!
      Telegram::ForumRelayService.handle_conversation_status_change(conversation)
      send_bot_topic_message(conversation, thread_id, "🚫 <b>该访客已成功拉黑屏蔽</b>\n会话已静音并标记解决，访客已被加入黑名单。")
      true
    when 'bind', '绑定'
      handle_bind_command(conversation, thread_id, from, cmd_args)
      true
    when 'del', 'recall', '撤回', '删除'
      handle_delete_command(conversation, thread_id, msg)
      true
    when 'note', '备注'
      if cmd_args.present?
        agent = find_agent_for_telegram_sender(account, from) || conversation.assignee || account.users.first
        conversation.messages.create!(
          account: account,
          inbox: conversation.inbox,
          message_type: :activity,
          private: true,
          content: cmd_args,
          sender: agent
        )
        send_bot_topic_message(conversation, thread_id, "📝 <b>内部私密备注已记录 (仅客服可见)</b>:\n#{CGI.escapeHTML(cmd_args)}")
      else
        send_bot_topic_message(conversation, thread_id, "⚠️ 请提供备注内容，例如: <code>/note 客户反馈香港02节点超时</code>")
      end
      true
    when 'tag', 'label', '标签'
      if cmd_args.present?
        labels = cmd_args.split(/[,，\s]+/).map(&:strip).reject(&:blank?)
        conversation.add_labels(labels)
        send_bot_topic_message(conversation, thread_id, "🏷️ <b>已添加会话标签</b>: #{CGI.escapeHTML(labels.join(', '))}")
      else
        send_bot_topic_message(conversation, thread_id, "⚠️ 请提供标签名，例如: <code>/tag 节点故障, 充值未到账</code>")
      end
      true
    when 'canned', 'quick', '快捷回复', '话术'
      canned_list = account.canned_responses.order(:short_code).limit(25)
      if canned_list.any?
        lines = canned_list.map do |cr|
          "• <code>/#{cr.short_code}</code> : #{CGI.escapeHTML(cr.content.truncate(45))}"
        end
        send_bot_topic_message(conversation, thread_id, "📋 <b>快捷预设话术列表</b> (直接发送 <code>/快捷码</code> 即可发给客户):\n\n#{lines.join("\n")}")
      else
        send_bot_topic_message(conversation, thread_id, "📋 暂无预设快捷话术，可在 Chatwoot 后台【设置 -> 快捷回复】中添加。")
      end
      true
    when 'help', '帮助'
      help_text = <<~HELP.strip
        💡 <b>Telegram 客服操作指令与快捷键指南</b>

        • <b>直接回复</b>: 发送文字/图片/动图/语音/文件，直接同步回复客户
        • <b>内联按钮</b>: 话题顶部卡片自带 <code>[刷新数据]</code> <code>[解决]</code> <code>[已留资]</code> <code>[拉黑]</code>
        • <code>/resolve</code>: 解决并关闭当前会话
        • <code>/reopen</code>: 重新打开已关闭会话
        • <code>/info</code>: 重新调出客户画像与订阅详情卡片
        • <code>/assign &lt;客服&gt;</code>: 将会话转接给指定客服 (如 <code>/assign 张三</code>)
        • <code>/block</code>: 一键拉黑恶意访客并关闭会话
        • <code>/bind &lt;邮箱&gt;</code>: 绑定 Telegram 身份至后台客服账户
        • <code>/del</code>: 撤回消息 (回复某条消息并发送 <code>/del</code>)
        • <code>/canned</code>: 查看所有快捷预设话术列表
        • <code>/&lt;快捷码&gt;</code>: 直接发送预设话术给客户 (如 <code>/clash</code>)
        • <code>/note &lt;内容&gt;</code>: 添加客服内部私密备注 (客户不可见)
        • <code>/tag &lt;标签&gt;</code>: 为会话打标签 (如 <code>/tag 充值问题</code>)
        • <code>/help</code>: 查看本指令帮助
      HELP
      send_bot_topic_message(conversation, thread_id, help_text)
      true
    else
      canned = account.canned_responses.find_by('lower(short_code) = ?', cmd)
      if canned.present?
        agent = find_agent_for_telegram_sender(account, from) || conversation.assignee || account.users.first
        conversation.messages.create!(
          account: account,
          inbox: conversation.inbox,
          message_type: :outgoing,
          content: canned.content,
          sender: agent,
          source_id: "telegram_canned_#{msg[:message_id]}"
        )
        send_bot_topic_message(conversation, thread_id, "🚀 <b>已发送快捷话术【#{canned.short_code}】给客户</b>:\n#{CGI.escapeHTML(canned.content)}")
        true
      else
        false
      end
    end
  end

  def handle_assign_command(conversation, thread_id, cmd_args)
    account = conversation.account
    users = account.users.to_a

    if cmd_args.blank?
      lines = users.map { |u| "• <code>/assign #{u.email}</code> (#{u.name})" }
      send_bot_topic_message(conversation, thread_id, "👥 <b>可用客服列表</b>:\n\n#{lines.join("\n")}\n\n💡 <i>提示: 发送 <code>/assign &lt;邮箱或名字&gt;</code> 即可转接。</i>")
      return
    end

    query = cmd_args.downcase.sub(/^@/, '')
    target_user = users.find do |u|
      u.email.to_s.downcase == query ||
        u.email.to_s.downcase.split('@').first == query ||
        u.name.to_s.downcase.include?(query) ||
        u.custom_attributes&.dig('telegram_username').to_s.downcase == query
    end

    if target_user.present?
      conversation.update!(assignee: target_user)
      send_bot_topic_message(conversation, thread_id, "🤝 <b>会话已成功转接！</b>\n当前会话已指派给客服: <b>#{CGI.escapeHTML(target_user.name)}</b> (<code>#{target_user.email}</code>)")
    else
      send_bot_topic_message(conversation, thread_id, "⚠️ 未找到匹配的客服【#{CGI.escapeHTML(cmd_args)}】，可发送 <code>/assign</code> 查看全部客服列表。")
    end
  end

  def handle_bind_command(conversation, thread_id, from, email_arg)
    account = conversation.account
    from_id = from[:id].to_s
    from_username = from[:username].to_s.sub(/^@/, '')
    from_name = [from[:first_name], from[:last_name]].compact.join(' ').presence || from_username || "TG-#{from_id.last(4)}"

    if email_arg.blank?
      send_bot_topic_message(conversation, thread_id, "⚠️ 请提供您的 Chatwoot 后台登录邮箱，例如: <code>/bind kf1@example.com</code>")
      return
    end

    target_user = account.users.find_by('lower(email) = ?', email_arg.downcase)
    if target_user.present?
      attrs = (target_user.custom_attributes || {}).merge(
        'telegram_user_id' => from_id,
        'telegram_username' => from_username
      )
      target_user.update_column(:custom_attributes, attrs)
      send_bot_topic_message(conversation, thread_id, "✅ <b>客服身份绑定成功！</b>\n已将 Telegram 用户 <b>#{CGI.escapeHTML(from_name)}</b> 绑定至后台客服：<code>#{target_user.email}</code> (#{target_user.name})。后续您的所有发言将以此客服身份同步给客户与后台。")
    else
      send_bot_topic_message(conversation, thread_id, "⚠️ 系统中未找到邮箱为 <code>#{CGI.escapeHTML(email_arg)}</code> 的客服账号，请检查拼写或在后台确认。")
    end
  end

  def handle_delete_command(conversation, thread_id, msg)
    account = conversation.account
    reply_msg = msg[:reply_to_message]
    unless reply_msg.present?
      send_bot_topic_message(conversation, thread_id, "⚠️ 请<b>引用/回复</b>您要撤回的那条消息，并输入 <code>/del</code>。")
      return
    end

    target_tg_id = reply_msg[:message_id]
    target_msg = conversation.messages.where("source_id = ? OR additional_attributes ->> 'telegram_message_id' = ?", "telegram_#{target_tg_id}", target_tg_id.to_s).last

    if target_msg.present?
      target_msg.update!(content: I18n.t('conversations.messages.deleted'), content_attributes: { deleted: true })
      target_msg.attachments.destroy_all rescue nil
    end

    gid = Telegram::ForumRelayService.group_id(account)
    HTTParty.post(Telegram::ForumRelayService.api_url('deleteMessage', account), body: { chat_id: gid, message_id: target_tg_id }) rescue nil
    HTTParty.post(Telegram::ForumRelayService.api_url('deleteMessage', account), body: { chat_id: gid, message_id: msg[:message_id] }) rescue nil
  end

  def find_agent_for_telegram_sender(account, from)
    return nil if account.blank? || from.blank?

    from_id = from[:id].to_s
    from_username = from[:username].to_s.downcase.sub(/^@/, '')
    from_full_name = [from[:first_name], from[:last_name]].compact.join(' ').strip

    users = account.users.to_a

    # 1. Match by custom_attributes['telegram_user_id']
    match = users.find { |u| u.custom_attributes&.dig('telegram_user_id').to_s == from_id }
    return match if match.present?

    # 2. Match by custom_attributes['telegram_username']
    if from_username.present?
      match = users.find { |u| u.custom_attributes&.dig('telegram_username').to_s.downcase == from_username }
      return match if match.present?

      # 3. Match by email prefix
      match = users.find { |u| u.email.to_s.split('@').first.downcase == from_username }
      return match if match.present?
    end

    # 4. Match by user display name or full name
    if from_full_name.present?
      match = users.find { |u| u.name.to_s.downcase == from_full_name.downcase || u.display_name.to_s.downcase == from_full_name.downcase }
      return match if match.present?
    end

    nil
  end

  def self.register_telegram_commands(bot_token)
    commands = [
      { command: 'resolve', description: '✅ 解决并关闭当前会话' },
      { command: 'info', description: '📊 刷新客户画像与订阅详情' },
      { command: 'assign', description: '👥 会话转接: /assign <客服名或邮箱>' },
      { command: 'block', description: '🚫 拉黑并屏蔽访客: /block' },
      { command: 'bind', description: '🔗 绑定客服账号: /bind <后台邮箱>' },
      { command: 'del', description: '🗑️ 撤回消息: 回复消息发送 /del' },
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
      allowed_updates: ['message', 'edited_message', 'callback_query']
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

    from = msg[:from] || {}
    matched_agent = find_agent_for_telegram_sender(conversation.account, from)
    agent = matched_agent || conversation.assignee || conversation.account.users.first

    from_full_name = [from[:first_name], from[:last_name]].compact.join(' ').strip
    tg_name = from_full_name.presence || (from[:username].present? ? "@#{from[:username]}" : "TG-#{from[:id].to_s.last(4)}")

    # If sender is not bound to a Chatwoot agent, prepend [TG客服: 张三]
    prefix = matched_agent.present? ? '' : "[TG客服: #{tg_name}]\n"

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

    raw_content = text.presence || default_content
    final_content = raw_content.present? ? "#{prefix}#{raw_content}" : nil

    message = conversation.messages.build(
      account: conversation.account,
      inbox: conversation.inbox,
      message_type: :outgoing,
      content: final_content,
      sender: agent,
      source_id: "telegram_#{msg[:message_id]}",
      content_attributes: {
        telegram_sender_id: from[:id].to_s,
        telegram_sender_username: from[:username].to_s,
        telegram_sender_name: tg_name
      }
    )

    attach_photo(message, photo_array) if photo_array.present?
    attach_animation(message, animation) if animation.present?
    attach_sticker(message, sticker) if sticker.present?
    attach_document(message, document) if document.present?
    attach_voice(message, voice || audio) if (voice || audio).present?
    attach_video(message, video) if video.present?

    # If visual media without custom caption, and sender is bound, clear text bubble
    if message.attachments.any? { |att| att.image? || att.video? } && msg[:text].blank? && msg[:caption].blank? && matched_agent.present?
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
