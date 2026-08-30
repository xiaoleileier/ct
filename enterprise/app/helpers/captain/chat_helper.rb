module Captain::ChatHelper
  def request_chat_completion
    log_chat_completion_request

    chat_params = {
      model: @model,
      messages: @messages,
      temperature: @assistant&.config&.[]('temperature').to_f || 1
    }

    tools = @tool_registry&.registered_tools
    chat_params[:tools] = tools if tools.present? && tools.any?

    response = @client.chat(parameters: chat_params)

    handle_response(response)
  rescue StandardError => e
    Rails.logger.error "#{self.class.name} Assistant: #{@assistant&.id}, Error in chat completion: #{e.message}"
    { 'content' => "AI 响应异常: #{e.message}" }
  end

  private

  def handle_response(response)
    Rails.logger.info { "#{self.class.name} Assistant: #{@assistant&.id}, Received response: #{response}" }

    if response.is_a?(Hash) && response['error'].present?
      err_msg = response.dig('error', 'message') || response['error'].to_s
      Rails.logger.error("LLM API Error: #{err_msg}")
      return { 'content' => "接口返回错误: #{err_msg}" }
    end

    message = response.dig('choices', 0, 'message')
    return { 'content' => '未能获取到回复内容，请检查模型与接口状态。' } if message.blank?

    if message['tool_calls'].present?
      process_tool_calls(message['tool_calls'])
    else
      content_str = message['content'].to_s.strip
      begin
        parsed = JSON.parse(content_str)
        result = parsed.is_a?(Hash) ? parsed : { 'content' => content_str }
      rescue JSON::ParserError
        result = { 'content' => content_str }
      end
      persist_message(result, 'assistant')
      result
    end
  end

  def process_tool_calls(tool_calls)
    append_tool_calls(tool_calls)
    tool_calls.each do |tool_call|
      process_tool_call(tool_call)
    end
    request_chat_completion
  end

  def process_tool_call(tool_call)
    arguments = JSON.parse(tool_call['function']['arguments'])
    function_name = tool_call['function']['name']
    tool_call_id = tool_call['id']

    if @tool_registry.respond_to?(function_name)
      execute_tool(function_name, arguments, tool_call_id)
    else
      process_invalid_tool_call(function_name, tool_call_id)
    end
  end

  def execute_tool(function_name, arguments, tool_call_id)
    persist_message(
      {
        content: I18n.t('captain.copilot.using_tool', function_name: function_name),
        function_name: function_name
      },
      'assistant_thinking'
    )
    result = @tool_registry.send(function_name, arguments)
    persist_message(
      {
        content: I18n.t('captain.copilot.completed_tool_call', function_name: function_name),
        function_name: function_name
      },
      'assistant_thinking'
    )
    append_tool_response(result, tool_call_id)
  end

  def append_tool_calls(tool_calls)
    @messages << {
      role: 'assistant',
      tool_calls: tool_calls
    }
  end

  def process_invalid_tool_call(function_name, tool_call_id)
    persist_message({ content: I18n.t('captain.copilot.invalid_tool_call'), function_name: function_name }, 'assistant_thinking')
    append_tool_response(I18n.t('captain.copilot.tool_not_available'), tool_call_id)
  end

  def append_tool_response(content, tool_call_id)
    @messages << {
      role: 'tool',
      tool_call_id: tool_call_id,
      content: content
    }
  end

  def log_chat_completion_request
    Rails.logger.info(
      "#{self.class.name} Assistant: #{@assistant.id}, Requesting chat completion
      for messages #{@messages} with #{@tool_registry&.registered_tools&.length || 0} tools
      "
    )
  end
end
