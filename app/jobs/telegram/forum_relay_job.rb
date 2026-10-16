# frozen_string_literal: true

class Telegram::ForumRelayJob < ApplicationJob
  queue_as :medium

  def perform(message_id)
    message = Message.find_by(id: message_id)
    return unless message
    return if message.source_id&.start_with?('telegram_')

    Telegram::ForumRelayService.new(message: message).perform
  end
end
