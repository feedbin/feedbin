module Dialog
  class SocialReplies < ApplicationComponent
    TITLE = "Replies"

    def initialize(posts:)
      @posts = posts
    end

    def view_template
      render Dialog::Template::Content.new(dialog_id: self.class.dom_id) do |dialog|
        dialog.title do
          TITLE
        end
        dialog.body do
          div class: "animate-fade-in" do
            render partial: 'microposts/thread', locals: {microposts: @posts}
          end
        end
      end
    end
  end
end
