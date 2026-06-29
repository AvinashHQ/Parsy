# frozen_string_literal: true

class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :require_authentication
  helper_method :current_user, :current_tenant

  private

  def require_authentication
    return if current_user

    redirect_to new_session_path, alert: "Sign in required"
  end

  def current_user
    return @current_user if defined?(@current_user)

    @current_user = User.includes(:tenant).find_by(id: session[:user_id])
    Current.user = @current_user
    Current.tenant = @current_user&.tenant
    @current_user
  end

  def current_tenant
    current_user&.tenant
  end

  def sign_in(user)
    reset_session
    session[:user_id] = user.id
    user.update!(last_authenticated_at: Time.current)
    Current.user = user
    Current.tenant = user.tenant
  end

  def sign_out
    reset_session
    Current.reset
  end
end
