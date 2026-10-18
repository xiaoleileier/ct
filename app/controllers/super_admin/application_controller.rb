# All Administrate controllers inherit from this
# `Administrate::ApplicationController`, making it the ideal place to put
# authentication logic or other before_actions.
#
# If you want to add pagination or other controller-level concerns,
# you're free to overwrite the RESTful controller actions.
class SuperAdmin::ApplicationController < Administrate::ApplicationController
  include ActionView::Helpers::TagHelper
  include ActionView::Context
  include SuperAdmin::NavigationHelper
  include SwitchLocale

  helper_method :render_vue_component, :settings_open?, :settings_pages
  # authenticiation done via devise : SuperAdmin Model
  before_action :authenticate_super_admin!
  around_action :switch_locale

  # Override this value to specify the number of elements to display at a time
  # on index pages. Defaults to 20.
  # def records_per_page
  #   params[:per_page] || 20
  # end

  def order
    @order ||= Administrate::Order.new(
      params.fetch(resource_name, {}).fetch(:order, 'id'),
      params.fetch(resource_name, {}).fetch(:direction, 'desc')
    )
  end

  private

  def locale_from_user
    super_admin = current_super_admin if respond_to?(:current_super_admin)
    super_admin&.ui_settings&.dig('locale') || ENV.fetch('DEFAULT_LOCALE', 'zh_CN')
  end

  def render_vue_component(component_name, props = {})
    html_options = {
      id: 'app',
      data: {
        component_name: component_name,
        props: props.to_json
      }
    }
    content_tag(:div, '', html_options)
  end

  def invalid_action_perfomed
    flash[:error] = I18n.t('super_admin.invalid_action', default: 'Invalid action performed')
    redirect_back(fallback_location: root_path)
  end
end
