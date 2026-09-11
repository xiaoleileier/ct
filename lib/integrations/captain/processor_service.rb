class Integrations::Captain::ProcessorService < Integrations::BotProcessorService
  pattr_initialize [:event_name!, :hook!, :event_data!]

  private

  def get_response(_session_id, message_content)
    call_captain(message_content)
  end

  def process_response(message, response)
    msg_content = message.content.to_s.strip
    resp_content = response.to_s.strip

    user_requested = msg_content.present? && msg_content.length <= 20 && msg_content =~ /(?:人工|真人|转人工|找客服|转客服)/i
    model_handoff = resp_content == 'conversation_handoff' ||
                    resp_content.include?('conversation_handoff') ||
                    resp_content =~ /(?:转接人工|转人工|为您转接|转给人工|排队等待中|专属客服|联系人工|转交人工|切换人工|接入人工|客服代表为您)/i

    if user_requested || model_handoff
      if resp_content.present? && resp_content != 'conversation_handoff' && !resp_content.include?('conversation_handoff')
        create_conversation(message, { content: response })
      end
      message.conversation.bot_handoff!
    else
      create_conversation(message, { content: response })
    end
  end

  def create_conversation(message, content_params)
    return if content_params.blank?

    conversation = message.conversation
    conversation.messages.create!(
      content_params.merge(
        {
          message_type: :outgoing,
          account_id: conversation.account_id,
          inbox_id: conversation.inbox_id
        }
      )
    )
  end

  def call_captain(message_content)
    url = "#{GlobalConfigService.load('CAPTAIN_API_URL',
                                      '')}/accounts/#{hook.settings['account_id']}/assistants/#{hook.settings['assistant_id']}/chat"

    headers = {
      'X-USER-EMAIL' => hook.settings['account_email'],
      'X-USER-TOKEN' => hook.settings['access_token'],
      'Content-Type' => 'application/json'
    }

    body = {
      message: message_content,
      previous_messages: previous_messages
    }

    response = HTTParty.post(url, headers: headers, body: body.to_json)
    response.parsed_response['message']
  end

  def previous_messages
    previous_messages = []
    conversation.messages.where(message_type: [:outgoing, :incoming]).where(private: false).offset(1).find_each do |message|
      next if message.content_type != 'text'

      role = determine_role(message)
      previous_messages << { message: message.content, type: role }
    end
    previous_messages
  end

  def determine_role(message)
    message.message_type == 'incoming' ? 'User' : 'Bot'
  end
end
