class AutomationRules::ActionService < ActionService
  def initialize(rule, account, conversation)
    super(conversation)
    @rule = rule
    @account = account
    Current.executed_by = rule
  end

  def perform
    @rule.actions.each do |action|
      @conversation.reload
      action = action.with_indifferent_access
      begin
        send(action[:action_name], action[:action_params])
      rescue StandardError => e
        ChatwootExceptionTracker.new(e, account: @account).capture_exception
      end
    end
  ensure
    Current.reset
  end

  private

  def send_attachment(blob_ids)
    return if conversation_a_tweet?

    return unless @rule.files.attached?

    blobs = ActiveStorage::Blob.where(id: blob_ids)

    return if blobs.blank?

    params = { content: nil, private: false, attachments: blobs }
    Messages::MessageBuilder.new(nil, @conversation, params).perform
  end

  def send_webhook_event(webhook_url)
    payload = @conversation.webhook_data.merge(event: "automation_event.#{@rule.event_name}")
    WebhookJob.perform_later(webhook_url[0], payload)
  end

  def send_message(message)
    return if conversation_a_tweet?

    params = { content: message[0], private: false, content_attributes: { automation_rule_id: @rule.id } }
    Messages::MessageBuilder.new(nil, @conversation, params).perform
  end

  def send_interactive_menu(params)
    return if conversation_a_tweet?

    menu_data = params[0]
    return if menu_data.blank?

    title = menu_data.is_a?(Hash) ? (menu_data['title'] || menu_data[:title]) : menu_data.to_s
    raw_options = menu_data.is_a?(Hash) ? (menu_data['options'] || menu_data[:options] || menu_data['items'] || menu_data[:items]) : ''

    options_list = if raw_options.is_a?(Array)
                     raw_options
                   elsif raw_options.is_a?(String)
                     raw_options.split(/[,，\n]/).map(&:strip).reject(&:blank?)
                   else
                     []
                   end

    items = options_list.map do |opt|
      opt_title = opt.is_a?(Hash) ? (opt['title'] || opt[:title]) : opt.to_s
      opt_value = opt.is_a?(Hash) ? (opt['value'] || opt[:value] || opt_title) : opt.to_s
      { title: opt_title, value: opt_value }
    end

    return if items.blank?

    message_params = {
      content: title,
      content_type: 'input_select',
      content_attributes: {
        items: items,
        automation_rule_id: @rule.id
      },
      private: false
    }

    Messages::MessageBuilder.new(nil, @conversation, message_params).perform
  end

  def add_private_note(message)
    return if conversation_a_tweet?

    params = { content: message[0], private: true, content_attributes: { automation_rule_id: @rule.id } }
    Messages::MessageBuilder.new(nil, @conversation.reload, params).perform
  end

  def send_email_to_team(params)
    teams = Team.where(id: params[0][:team_ids])

    teams.each do |team|
      TeamNotifications::AutomationNotificationMailer.conversation_creation(@conversation, team, params[0][:message])&.deliver_now
    end
  end
end
