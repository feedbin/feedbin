module Dialog

  class EditSavedSearch < ApplicationComponent
    TITLE = "Edit Saved Search"

    def initialize(saved_search:)
      @saved_search = saved_search
    end

    def view_template
      render Dialog::SavedSearchForm.new(saved_search: @saved_search, title: TITLE, dialog_id: self.class.dom_id)
    end
  end
end
