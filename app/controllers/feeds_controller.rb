class FeedsController < ApplicationController

  before_action :correct_user, only: :update
  skip_before_action :authorize, only: [:push]
  skip_before_action :verify_authenticity_token, only: [:push]

  def update
    @user = current_user
    @feed = Feed.find(params[:id])
    taggings = @feed.tag(params[:feed][:tag_list], @user)

    # Open the tag drawer this was just added to
    session[:tag_visibility] ||= {}
    taggings.each do |tagging|
      session[:tag_visibility][tagging.tag_id.to_s] = true
    end

    @mark_selected = true
    get_feeds_list
    respond_to do |format|
      format.js
    end
  end

  def view_unread
    update_view_mode('view_unread')
  end

  def view_all
    # Clear the hide queue when switching to view_all incase there's anything sitting in it.
    @clear_hide_queue = true
    update_view_mode('view_all')
  end

  def auto_update
    @keep_selected = true
    if session[:view_mode] == 'view_all'
      view_all
    else
      view_unread
    end
  end

  def push
    if request.get?
      if params['hub.mode'] == 'subscribe'
        @feed = Feed.find(params[:id])
        if @feed.feed_url != params['hub.topic']
          render_404
        else
          @feed.update_attributes(:push_expiration => Time.now + (params['hub.lease_seconds'].to_i/2).seconds)
          render :text => params['hub.challenge']
        end
      else
        # Handle unsubscriptions confirmation
        render_404
      end
    else
      @feed = Feed.find(params[:id])
      secret = Digest::SHA1.hexdigest([@feed.id, ENV["SECRET_KEY_BASE"]].join('-'))
      body = request.body.read
      signature = OpenSSL::HMAC.hexdigest('sha1', secret, body)
      if request.headers['HTTP_X_HUB_SIGNATURE'] == ["sha1", signature].join('=')
        Sidekiq::Client.push_bulk(
                                  'args'  => [[@feed.id, @feed.feed_url, nil, nil, @feed.subscriptions_count, body]],
                                  'class' => 'FeedRefresherFetcher',
                                  'queue' => 'feed_refresher_fetcher',
                                  'retry' => false
                                  )
      else
        logger.error("Non matching signature on PubsubHubbub notification. We get #{request.headers['HTTP_X_HUB_SIGNATURE']} when we expected #{["sha1", signature].join('=')}")
      end
      render :nothing => true
    end
  end

  private

  def update_view_mode(view_mode)
    @user = current_user
    @view_mode = view_mode
    session[:view_mode] = @view_mode

    @mark_selected = true
    get_feeds_list
    respond_to do |format|
      format.js { render partial: 'shared/update_view_mode' }
    end
  end

  def correct_user
    unless current_user.subscribed_to?(params[:id])
      render_404
    end
  end

end
