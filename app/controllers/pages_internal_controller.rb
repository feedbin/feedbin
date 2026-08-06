class PagesInternalController < ApplicationController

  def create
    @entry = SavePage.new.perform(current_user.id, params[:url], nil)
    get_feeds_list
  rescue SavePage::MissingPage => exception
    # Same as Api::V2::PagesController: the entry exists, the extractor just
    # could not fill it in. Without the retry nothing ever re-crawls it.
    SavePage.perform_async(current_user.id, params[:url], nil)
    @entry = exception.entry
    get_feeds_list
    render :create
  end
end
