class TagsController < ApplicationController

  before_action :user_owns_tag, only: [:show]

  def index
    @user = current_user
    @tags = @user.feed_tags.pluck(:name)

    @tags = @tags.find_all { |tag| tag.downcase.include?(params[:query].downcase) }.first(3)
    respond_to do |format|
      format.json { render json: { suggestions: @tags.map {|tag| { value: tag, data: tag } } }.to_json }
    end
  end

  def show
    @user = current_user
    update_selected_feed!("tag", params[:id])

    @tag = Tag.find(params[:id])
    @feed_ids = Tagging.where(tag_id: @tag, user_id: @user).pluck(:feed_id)

    feeds_response

    @append = !params[:page].nil?

    @type = 'tag'
    @data = params[:id]

    @collection_title = @tag.name
    @collection_favicon = 'favicon-tag'

    respond_to do |format|
      format.js { render partial: 'shared/entries' }
    end
  end

  def update

    @user = current_user
    tag_name = params[:tag][:name].chomp.gsub(',', '')

    tag = Tag.find(params[:id])
    @taggings = Tagging.where(tag_id: tag, user_id: @user)
    @feed_ids = @taggings.pluck(:feed_id)

    @new_tag = nil
    if !tag_name.empty?
      ActiveRecord::Base.transaction do
        @new_tag = Tag.where(name: tag_name).first_or_create
        @taggings.update_all(tag_id: @new_tag.id)
      end
      update_selected_feed!("tag", @new_tag.try(:id))

      session[:tag_visibility] ||= {}
      session[:tag_visibility][@new_tag.id.to_s] = session[:tag_visibility][tag.id.to_s] ? session[:tag_visibility][tag.id.to_s] : false
    else
      # Tag is empty, delete taggings
      @taggings.destroy_all
    end

    get_feeds_list
    respond_to do |format|
      format.js
    end

  end

  def destroy
    @user = current_user
    tag = Tag.find(params[:id])
    Tagging.where(tag_id: tag, user_id: @user).destroy_all

    get_feeds_list

    respond_to do |format|
      format.js
    end

  end

  private

  def user_owns_tag
    @user = current_user
    tags = Tagging.where(user_id: @user, tag_id: params[:id].to_i)
    unless tags.any?
      render_404
    end
  end

end
