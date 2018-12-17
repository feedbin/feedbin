class SavedSearchPresenter < BasePresenter
  presents :saved_search

  def name
    if saved_search.name.blank?
      "Untitled Saved Search"
    else
      saved_search.name
    end
  end
end
