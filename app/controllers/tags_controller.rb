class TagsController < ApplicationController
  def index
    @user = current_user
    @tags = @user.feed_tags.pluck(:name)

    @tags = @tags.find_all { |tag| tag.downcase.include?(params[:query].downcase) }.first(3)
    respond_to do |format|
      format.json { render json: {suggestions: @tags.map { |tag| {value: tag, data: tag} }}.to_json }
    end
  end

  def edit
    @tag = authorized_tag or return
  end

  def show
    @user = current_user

    @tag = authorized_tag or return
    @feed_ids = Tagging.where(tag_id: @tag, user_id: @user).pluck(:feed_id)

    feeds_response

    @collection_title = @tag.name

    respond_to do |format|
      format.js { render partial: "shared/entries" }
    end
  end

  def update
    @new_tag = nil

    user = current_user

    tag = authorized_tag or return
    @new_tag = Tag.rename(user, tag, params[:tag][:name])

    if @new_tag
      visibility = user.tag_visibility[tag.id.to_s] || false
      user.update_tag_visibility(@new_tag.id.to_s, visibility)
    end

    get_feeds_list
  end

  def destroy
    @user = current_user
    tag = authorized_tag or return

    Tag.destroy(@user, tag)

    get_feeds_list

    respond_to do |format|
      format.js
    end
  end
end
