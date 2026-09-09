class SavedSearchesController < ApplicationController
  def show
    @user = current_user
    @saved_search = SavedSearch.where(user: @user, id: params[:id]).take!

    params[:query] = @saved_search.query

    result = Entry.scoped_search(params, @user)
    @entries = result.records(Entry).with_list_associations
    @page_query = result.pagination

    @append = params[:page].present?

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
    @saved_search = @user.saved_searches.new(saved_search_params)
    unless @saved_search.save
      return render_save_failure
    end
    get_feeds_list
  end

  def new
    @saved_search = @user.saved_searches.build(query: params[:query])
  end

  def update
    @user = current_user
    @saved_search = SavedSearch.where(user: @user, id: params[:id]).take!
    unless @saved_search.update(saved_search_params)
      return render_save_failure
    end
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

  # Both views address the record by id, so there is nothing for them to render
  # when it was never saved. Show the user why instead.
  def render_save_failure
    flash[:error] = @saved_search.errors.full_messages.join(". ")
    flash.discard
    render partial: "shared/message_flash", locals: {flash: flash}
  end

  def saved_search_params
    params.require(:saved_search).permit(:query, :name)
  end
end
