class PagesController < ApplicationController
  skip_before_action :authorize, only: [:options]

  after_action :cors_headers, only: [:create, :options]

  def create
    SavePage.perform_async(current_user.id, params[:url], params[:title])
  end

  def options
    head :ok
  end

  private

  # The bookmarklet and the extension post cross-origin, so they carry their own
  # credential rather than a forgery token. A request that authenticated on the
  # session cookie alone gets the normal check.
  def verify_authenticity_token
    super if params[:page_token].blank? && request.authorization.blank?
  end

  def authorize
    @current_user ||= begin
      if signed_in?
        current_user
      elsif params[:page_token]
        User.find_by_page_token!(params[:page_token])
      else
        authenticate_or_request_with_http_basic("Feedbin") do |username, password|
          User.where("lower(email) = ?", username.try(:downcase)).take.try(:authenticate, password)
        end
      end
    end
  end

  def cors_headers
    headers["Access-Control-Allow-Origin"] = "*"
    headers["Access-Control-Allow-Methods"] = "POST, OPTIONS"
    headers["Access-Control-Allow-Headers"] = "Origin, Content-Type, Accept"
    headers["Access-Control-Max-Age"] = 1.hour.to_i.to_s
  end
end
