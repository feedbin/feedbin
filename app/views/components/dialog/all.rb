module Dialog
  class All < ApplicationComponent

    def view_template
      render Dialog::Template.new
      render Dialog::KeyboardShortcuts.new
      render Dialog::AddFeed.new
      render Dialog::SettingsNav.new
      render Dialog::Template::Placeholder.new(dialog: Dialog::ExtractedContent)
      render Dialog::Template::Placeholder.new(dialog: Dialog::EditSubscription)
      render Dialog::Template::Placeholder.new(dialog: Dialog::EditAppearance)
      render Dialog::Template::Placeholder.new(dialog: Dialog::SocialReplies)
      render Dialog::Template::Placeholder.new(dialog: Dialog::EditTag, size: :xs)
      render Dialog::Template::Placeholder.new(dialog: Dialog::EditSavedSearch, size: :sm)
    end
  end
end