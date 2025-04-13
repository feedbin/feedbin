module Dialog
  class Mutes < ApplicationComponent
    TITLE = "Manage Mutes"

    def initialize(mutes:)
      @mutes = mutes
    end

    def view_template
      render Dialog::Template::Content.new(dialog_id: self.class.dom_id) do |dialog|
        dialog.title do
          TITLE
        end
        dialog.body do
          render Actions::MutesComponent.new(mutes: @mutes, user: current_user, remote: true)
        end
      end
    end
  end
end
