class FaviconsController < ApplicationController

  def index
    @user = current_user
    feed_ids = @user.subscriptions.pluck(:feed_id)
    hosts = Feed.where(id: feed_ids).pluck(:host)
    @favicons = Favicon.where(host: hosts)
    unless params[:hash] == 'none'
      expires_in 1.year, public: true
    end
  end

end
