class BookmarkletController < ApplicationController

  skip_before_action :verify_authenticity_token
  skip_before_action :authorize

  def script
    url = ActionController::Base.helpers.asset_url("bookmarklet.js", host: ENV['ASSET_HOST'])
    redirect_to url, status: :found
  end

end
