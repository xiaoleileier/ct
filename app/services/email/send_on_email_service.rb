class Email::SendOnEmailService < Base::SendOnChannelService
  private

  def channel_class
    Channel::Email
  end

  def perform_reply
    return unless message.email_notifiable_message?

    reply_mail = ConversationReplyMailer.with(account: message.account).email_reply(message).deliver_now
    raise StandardError, 'Failed to send email: SMTP is not configured or delivery returned nil' if reply_mail.nil?

    message_source_id = reply_mail.try(:message_id) || reply_mail.try(:header)&.try(:[], 'Message-ID')&.try(:value)
    Rails.logger.info("Email message #{message.id} sent with source_id: #{message_source_id}")
    message.update(source_id: message_source_id) if message_source_id.present?
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: message.account).capture_exception
    Messages::StatusUpdateService.new(message, 'failed', e.message).perform
  end
end
