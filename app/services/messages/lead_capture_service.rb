class Messages::LeadCaptureService
  pattr_initialize [:message!]

  def perform
    return unless message.incoming?
    return if message.content.blank?

    extract_lead_info
  end

  private

  delegate :conversation, to: :message
  delegate :contact, :account, to: :conversation

  def extract_lead_info
    content = message.content.to_s
    captured = false

    # 1. 匹配 11 位中国手机号 (13x-19x)
    phone_match = content.match(/(?<!\d)(1[3-9]\d{9})(?!\d)/)
    if phone_match && contact.phone_number.blank?
      formatted_phone = "+86#{phone_match[1]}"
      contact.update(phone_number: formatted_phone) rescue nil
      captured = true
    elsif phone_match
      captured = true
    end

    # 2. 匹配微信号
    wechat_match = content.match(/(?:微信|vx|vx号|加v|v信|wx)[:：\s]*([a-zA-Z][a-zA-Z0-9_-]{5,19})/i)
    if wechat_match
      wechat_id = wechat_match[1]
      contact.custom_attributes ||= {}
      contact.custom_attributes['wechat'] = wechat_id
      contact.save rescue nil
      captured = true
    end

    # 3. 匹配电子邮箱
    email_match = content.match(/[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/)
    if email_match && contact.email.blank?
      contact.update(email: email_match[0]) rescue nil
      captured = true
    elsif email_match
      captured = true
    end

    return unless captured

    # 为会话自动打上“已留资”标签
    conversation.reload.add_labels(['已留资']) rescue nil
  end
end
