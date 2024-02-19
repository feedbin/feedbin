class Admin::FeedsController < ApplicationController
  def index
    feed = if params.key?(:q)
      find_by = (params[:q].to_i == 0) ? {feed_url: params[:q]} : {id: params[:q]}
      Feed.where(find_by)
    end

    render Admin::Feeds::IndexView.new(params: params, feed: feed), layout: "settings"
  end
end
