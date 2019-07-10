class PagesController < ApplicationController

  skip_before_action :verify_authenticity_token
  skip_before_action :authorize

  def create
    user = User.find_by_page_token(params[:page_token])
    SavePage.perform_async(user.id, params[:url])
  end
end
