module Actions
  class MutesComponent < ApplicationComponent
    def initialize(mutes:, user:, remote: false)
      @mutes = mutes
      @subscriptions = user.subscriptions.index_by(&:feed_id)
      @remote = remote
    end

    def title(mute)
      if mute.all_feeds?
        "All Feeds"
      elsif subscription = @subscriptions[mute.computed_feed_ids.first]
        subscription.title || @subscription.feed.title
      end
    end

    def view_template
      if @mutes.present?
        @mutes.each do |mute|
          render Settings::ControlGroupComponent.new class: "group mb-2", data: {capsule: "true"} do |group|
            group.item do
              div class: "p-4 flex items-center gap-6" do
                div class: "truncate" do
                  mute.query
                end
                div class: "ml-auto flex items-center gap-4" do
                  div class: "truncate text-500" do
                    truncate title(mute), length: 20, omission: "…"
                  end

                  link_to mute_path(mute), method: :delete, remote: @remote, class: "cursor-pointer", title: "Delete Mute", data: {confirm: "Are you sure?", toggle: "tooltip"} do
                    Icon("menu-icon-delete")
                  end
                end
              end
            end
          end
        end
      else
        div class: "text-500 text-center sm:py-8" do
          "No mutes"
        end
      end
    end
  end
end
