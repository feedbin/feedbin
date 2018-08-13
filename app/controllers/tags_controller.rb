class TagsController < ApplicationController
  before_action :user_owns_tag, only: [:show]

  def index
    @user = current_user
    @tags = @user.feed_tags.pluck(:name)

    @tags = @tags.find_all { |tag| tag.downcase.include?(params[:query].downcase) }.first(3)
    respond_to do |format|
      format.json { render json: {suggestions: @tags.map { |tag| {value: tag, data: tag} }}.to_json }
    end
  end

  def show
    @user = current_user
    update_selected_feed!("tag", params[:id])

    @tag = Tag.find(params[:id])
    @feed_ids = Tagging.where(tag_id: @tag, user_id: @user).pluck(:feed_id)

    feeds_response

    @append = params[:page].present?

    @type = "tag"
    @data = params[:id]

    @collection_title = @tag.name

    respond_to do |format|
      format.js { render partial: "shared/entries" }
    end
  end

  def update
    @new_tag = nil

    user = current_user
    tag = Tag.find(params[:id])

    taggings = user.taggings.where(tag: tag)
    feed_ids = taggings.pluck(:feed_id)
    tag_name = params[:tag][:name].strip.gsub(",", "")

    if tag_name.present?
      ActiveRecord::Base.transaction do
        @new_tag = Tag.where(name: tag_name).first_or_create
        taggings.update_all(tag_id: @new_tag.id)
      end
      update_selected_feed!("tag", @new_tag.id)
      visibility = user.tag_visibility[tag.id.to_s] ? user.tag_visibility[tag.id.to_s] : false
      user.update_tag_visibility(@new_tag.id.to_s, visibility)

      ActionTags.perform_async(user.id, @new_tag.id, tag.id)
    end

    get_feeds_list
    respond_to :js
  end

  def destroy
    @user = current_user
    tag = Tag.find(params[:id])
    Tagging.where(tag_id: tag, user_id: @user).destroy_all

    ActionTags.perform_async(@user.id, nil, tag.id)

    get_feeds_list

    respond_to do |format|
      format.js
    end
  end

  private

  def user_owns_tag
    @user = current_user
    tags = Tagging.where(user_id: @user, tag_id: params[:id].to_i)
    if tags.count.zero?
      render_404
    end
  end
end
