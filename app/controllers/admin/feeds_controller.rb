class Admin::FeedsController < ApplicationController
  def index
    feed = if params.key?(:q)
      # key? says the key is there, not that it holds a scalar: ?q[]=1 gives an
      # Array and ?q[a]=1 gives Parameters, neither of which responds to to_i.
      query = params[:q].is_a?(String) ? params[:q] : ""
      find_by = (query.to_i == 0) ? {feed_url: query} : {id: query}
      Feed.where(find_by)
    end

    render Admin::Feeds::IndexView.new(params: params, feed: feed), layout: "settings"
  end
end
