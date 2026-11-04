# frozen_string_literal: true

class Telegram::ForumRelayJob < MutexApplicationJob
  queue_as :medium
  retry_on LockAcquisitionError, wait: 0.5.seconds, attempts: 20

  def perform(message_id)
    message = Message.find_by(id: message_id)
    return unless message
    return if message.source_id&.start_with?('telegram_')
    return if message.private?
    return if message.activity?
    return if message.input_csat?

    key = format(::Redis::Alfred::TELEGRAM_RELAY_MUTEX, conversation_id: message.conversation_id)
    with_lock(key, 20.seconds) do
      Telegram::ForumRelayService.new(message: message).perform
    end
  end
end
