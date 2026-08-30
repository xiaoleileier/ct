class Captain::Conversation::ResponseBuilderJob < ApplicationJob
  MAX_MESSAGE_LENGTH = 10_000
  retry_on ActiveStorage::FileNotFoundError, attempts: 3, wait: 2.seconds
  retry_on Faraday::BadRequestError, attempts: 3, wait: 2.seconds

  def perform(conversation, assistant)
    @conversation = conversation
    @inbox = conversation.inbox
    @assistant = assistant

    Current.executed_by = @assistant

    ActiveRecord::Base.transaction do
      generate_and_process_response
    end
  rescue StandardError => e
    raise e if e.is_a?(ActiveStorage::FileNotFoundError) || e.is_a?(Faraday::BadRequestError)

    handle_error(e)
  ensure
    Current.executed_by = nil
  end

  private

  delegate :account, :inbox, to: :@conversation

  def generate_and_process_response
    @response = if captain_v2_enabled?
                  Captain::Assistant::AgentRunnerService.new(assistant: @assistant, conversation: @conversation).generate_response(
                    message_history: collect_previous_messages
                  )
                else
                  Captain::Llm::AssistantChatService.new(assistant: @assistant).generate_response(
                    message_history: collect_previous_messages
                  )
                end

    return process_action('handoff') if handoff_requested?

    create_messages
    Rails.logger.info("[CAPTAIN][ResponseBuilderJob] Incrementing response usage for #{account.id}")
    account.increment_response_usage
  end

  def collect_previous_messages
    @conversation
      .messages
      .where(message_type: [:incoming, :outgoing])
      .where(private: false)
      .map do |message|
      message_hash = {
        content: prepare_multimodal_message_content(message),
        role: determine_role(message)
      }

      # Include agent_name if present in additional_attributes
      message_hash[:agent_name] = message.additional_attributes['agent_name'] if message.additional_attributes&.dig('agent_name').present?

      message_hash
    end
  end

  def determine_role(message)
    message.message_type == 'incoming' ? 'user' : 'assistant'
  end

  def prepare_multimodal_message_content(message)
    Captain::OpenAiMessageBuilderService.new(message: message).generate_content
  end

  def handoff_requested?
    return false if @response.blank?

    resp = @response['response'] || @response[:response] || @response['content'] || @response[:content] || @response.to_s
    resp_str = resp.to_s.strip

    resp_str == 'conversation_handoff' || resp_str.include?('conversation_handoff')
  end

  def process_action(action)
    case action
    when 'handoff'
      I18n.with_locale(@assistant.account.locale) do
        create_handoff_message
        @conversation.bot_handoff!
      end
    end
  end

  def create_handoff_message
    msg = @assistant.config['handoff_message'].presence || I18n.t('conversations.captain.handoff', default: '正在转接人工客服以获得进一步协助。')
    create_outgoing_message(msg)
  end

  def create_messages
    content = @response['response'] || @response[:response] || @response['content'] || @response[:content]

    # Defensive parsing: if content is still a JSON string or markdown block
    if content.to_s.include?('"response"') || content.to_s.include?('"reasoning"') || content.to_s.start_with?('```')
      clean_str = content.to_s.gsub(/\A```(?:json)?\s*/i, '').gsub(/\s*```\z/, '').strip
      begin
        parsed = JSON.parse(clean_str)
        content = parsed['response'] || parsed['result'] || parsed['content'] || clean_str if parsed.is_a?(Hash)
      rescue JSON::ParserError
        if clean_str =~ /"response"\s*:\s*"((?:[^"\\]|\\.)*)"/m
          content = $1.gsub(/\\"/, '"').gsub(/\\n/, "\n").gsub(/\\\\/, '\\')
        end
      end
    end

    agent_name = @response['agent_name'] || @response[:agent_name]
    validate_message_content!(content)
    create_outgoing_message(content, agent_name: agent_name)
  end

  def validate_message_content!(content)
    raise ArgumentError, 'Message content cannot be blank' if content.blank?
  end

  def create_outgoing_message(message_content, agent_name: nil)
    additional_attrs = {}
    additional_attrs[:agent_name] = agent_name if agent_name.present?

    @conversation.messages.create!(
      message_type: :outgoing,
      account_id: account.id,
      inbox_id: inbox.id,
      sender: @assistant,
      content: message_content,
      additional_attributes: additional_attrs
    )
  end

  def handle_error(error)
    log_error(error)
    process_action('handoff')
    true
  end

  def log_error(error)
    ChatwootExceptionTracker.new(error, account: account).capture_exception
  end

  def captain_v2_enabled?
    return account.feature_enabled?('captain_integration_v2')
  end
end
