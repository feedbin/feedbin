class PagesInternalController < ApplicationController

  def create
    @entry = SavePage.new.perform(current_user.id, params[:url], nil)
    get_feeds_list
  end
end
