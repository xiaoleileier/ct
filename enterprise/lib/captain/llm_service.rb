require 'openai'

class Captain::LlmService
  def initialize(config)
    api_key = config[:api_key].presence || InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY')&.value
    endpoint = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value.to_s.strip.chomp('/')
    endpoint = 'https://api.openai.com' if endpoint.blank?
    uri_base = endpoint.end_with?('/v1') ? endpoint : "#{endpoint}/v1"

    @client = OpenAI::Client.new(
      access_token: api_key,
      uri_base: uri_base,
      log_errors: Rails.env.development?
    )
    @model = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value.presence || 'gpt-4o'
    @logger = Rails.logger
  end

  def call(messages, functions = [])
    openai_params = {
      model: @model,
      response_format: { type: 'json_object' },
      messages: messages
    }
    openai_params[:tools] = functions if functions.any?

    response = @client.chat(parameters: openai_params)
    handle_response(response)
  rescue StandardError => e
    handle_error(e)
  end

  private

  def handle_response(response)
    if response['choices'][0]['message']['tool_calls']
      handle_tool_calls(response)
    else
      handle_direct_response(response)
    end
  end

  def handle_tool_calls(response)
    tool_call = response['choices'][0]['message']['tool_calls'][0]
    {
      tool_call: tool_call,
      output: nil,
      stop: false
    }
  end

  def handle_direct_response(response)
    content = response.dig('choices', 0, 'message', 'content').to_s.strip
    clean_str = content.gsub(/\A```(?:json)?\s*/i, '').gsub(/\s*```\z/, '').strip

    begin
      parsed = JSON.parse(clean_str)
      out = parsed['response'] || parsed['result'] || parsed['content'] || parsed['thought_process'] || clean_str
      {
        output: out,
        stop: parsed['stop'] || false
      }
    rescue JSON::ParserError
      if clean_str =~ /"response"\s*:\s*"((?:[^"\\]|\\.)*)"/m
        res = $1.gsub(/\\"/, '"').gsub(/\\n/, "\n").gsub(/\\\\/, '\\')
        return { output: res, stop: false }
      end
      { output: clean_str, stop: false }
    end
  end

  def handle_error(error, content = nil)
    @logger.error("LLM call failed: #{error.message}")
    @logger.error(error.backtrace.join("\n"))
    @logger.error("Content: #{content}") if content

    { output: 'Error occurred, retrying', stop: false }
  end
end
