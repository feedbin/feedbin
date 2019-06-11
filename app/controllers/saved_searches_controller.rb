class SavedSearchesController < ApplicationController
  def show
    @user = current_user
    @saved_search = SavedSearch.where(user: @user, id: params[:id]).take!

    update_selected_feed!("saved_search", params[:id])

    params[:query] = @saved_search.query

    query = Entry.scoped_search(params, @user)
    @entries = query.records
    @page_query = query

    @append = params[:page].present?

    @type = "saved_search"
    @data = nil

    @collection_title = @saved_search.name

    respond_to do |format|
      format.js { render partial: "shared/entries" }
    end
  end

  def edit
    @user = current_user
    @saved_search = @user.saved_searches.find(params[:id])
  end

  def create
    @user = current_user
    @saved_search = @user.saved_searches.create(saved_search_params)
    get_feeds_list
  end

  def new
    @saved_search = @user.saved_searches.build(query: params[:query])
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

  def count
    @user = current_user
    @count = Entry.saved_search_count(@user) || []
  end

  private

  def saved_search_params
    params.require(:saved_search).permit(:query, :name)
  end
end
