# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

class Messages::TranslationService
  pattr_initialize [:message, :target_language]

  def self.translate_raw_text(text, target_lang = 'en')
    return '' if text.blank?

    source_lang = text.match?(/[\u4e00-\u9fa5]/) ? 'zh-CN' : 'en'
    target_lang = 'zh-CN' if target_lang.to_s.downcase.include?('zh')

    return text if source_lang == target_lang

    langpair = "#{source_lang}|#{target_lang}"
    encoded = URI.encode_www_form_component(text[0..500])
    uri = URI("https://api.mymemory.translated.net/get?q=#{encoded}&langpair=#{langpair}")

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 4
    http.read_timeout = 4

    request = Net::HTTP::Get.new(uri)
    response = http.request(request)

    if response.is_a?(Net::HTTPSuccess)
      data = JSON.parse(response.body)
      data.dig('responseData', 'translatedText') || text
    else
      text
    end
  rescue StandardError => e
    Rails.logger.warn "Translation failed: #{e.message}"
    text
  end

  def perform
    if google_translate_hook_present?
      google_result = Integrations::GoogleTranslate::ProcessorService.new(
        message: message,
        target_language: target_language
      ).perform
      return google_result if google_result.present?
    end

    content = message.content.to_s
    self.class.translate_raw_text(content, target_language)
  end

  private

  def google_translate_hook_present?
    hook = message.account.hooks.find_by(app_id: 'google_translate', status: 'enabled')
    hook.present?
  end
end
