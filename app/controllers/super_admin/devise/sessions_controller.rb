# frozen_string_literal: true

class SuperAdmin::Devise::SessionsController < Devise::SessionsController
  include SwitchLocale
  around_action :switch_locale

  def new
    self.resource = resource_class.new(sign_in_params)
  end

  def create
    redirect_to(super_admin_session_path, flash: { error: @error_message }) && return unless valid_credentials?

    sign_in(:super_admin, @super_admin)
    flash.discard
    redirect_to super_admin_users_path
  end

  def destroy
    sign_out
    flash.discard
    redirect_to '/'
  end

  private

  def locale_from_user
    ENV.fetch('DEFAULT_LOCALE', 'zh_CN')
  end

  def valid_credentials?
    @super_admin = SuperAdmin.find_by!(email: params[:super_admin][:email])
    raise StandardError, 'Invalid Password' unless @super_admin.valid_password?(params[:super_admin][:password])

    true
  rescue StandardError => e
    Rails.logger.error e.message
    @error_message = I18n.t('super_admin.devise.sessions.invalid_credentials', default: '邮箱或密码错误，请重试。')
    false
  end
end
