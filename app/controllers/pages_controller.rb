class PagesController < ApplicationController

  skip_before_action :verify_authenticity_token

  after_action :cors_headers

  def create
    SavePage.perform_async(current_user.id, params[:url], params[:title])
  end

  def options
    head :ok
  end

  private

  def authorize
    @current_user ||= begin
      if params[:page_token]
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
