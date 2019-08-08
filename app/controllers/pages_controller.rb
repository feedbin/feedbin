class PagesController < ApplicationController

  skip_before_action :verify_authenticity_token
  skip_before_action :authorize

  after_action :cors_headers

  def create
    user = User.find_by_page_token!(params[:page_token])
    SavePage.perform_async(user.id, params[:url], params[:title])
  end

  def options
    head :ok
  end

  private

  def cors_headers
    headers["Access-Control-Allow-Origin"] = "*"
    headers["Access-Control-Allow-Methods"] = "POST, OPTIONS"
    headers["Access-Control-Allow-Headers"] = "Origin, Content-Type, Accept"
    headers["Access-Control-Max-Age"] = 1.hour.to_i.to_s
  end

end
