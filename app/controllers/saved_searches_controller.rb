class SavedSearchesController < ApplicationController

  def show
    @user = current_user
    @saved_search = SavedSearch.where(user: @user, id: params[:id]).take!

    update_selected_feed!("saved_search", params[:id])

    params[:query] = @saved_search.query

    @entries = Entry.search(params, @user)
    @entries = update_with_state(@entries)
    @page_query = @entries

    @append = !params[:page].nil?

    @type = 'saved_search'
    @data = nil

    @collection_title = @saved_search.name
    @collection_favicon = 'favicon-search'

    respond_to do |format|
      format.js { render partial: 'shared/entries' }
    end
  end

  def create
    @user = current_user
    @saved_search = @user.saved_searches.create(saved_search_params)
    get_feeds_list
  end

  def edit
    @user = current_user
    @saved_search = SavedSearch.where(user: @user, id: params[:id]).take!
  end

  def update
    @user = current_user
    @saved_search = SavedSearch.where(user: @user, id: params[:id]).take!
    @saved_search.update(saved_search_params)
    get_feeds_list
  end

  def destroy
    @user = current_user
    @saved_search = SavedSearch.where(user: @user, id: params[:id]).take!
    @saved_search.destroy
    get_feeds_list
  end

  private

  def saved_search_params
    params.require(:saved_search).permit(:query, :name)
  end

end
