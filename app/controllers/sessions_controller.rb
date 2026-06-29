# frozen_string_literal: true

class SessionsController < ApplicationController
  skip_before_action :require_authentication, only: %i[new create]

  def new
  end

  def create
    user = User.find_by(email: params[:email].to_s.downcase)
    if user&.authenticate_operator_token(params[:operator_token])
      sign_in(user)
      redirect_to review_batches_path, notice: "Signed in"
    else
      redirect_to new_session_path, alert: "Invalid operator credentials"
    end
  end

  def destroy
    sign_out
    redirect_to new_session_path, notice: "Signed out"
  end
end
