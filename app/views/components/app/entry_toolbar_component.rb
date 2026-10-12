module App
  # The one entry toolbar in the page. It renders no entry: the entry-toolbar
  # controller fills it from the toolbar data each entry carries, and sends
  # the star, read, extract, and delete requests itself. The markup classes
  # are the ones entries/_show.html.erb used, so the toolbar styles still apply.
  class EntryToolbarComponent < ApplicationComponent
    STIMULUS_CONTROLLER = :entry_toolbar

    # The controller swaps these for the ids of the open entry.
    ENTRY_ID = "ENTRY_ID"
    FEED_ID = "FEED_ID"

    def view_template
      div class: "toolbar-wrap group", data: controller_data do
        textarea id: "source_link_field", name: "source_link_field", class: "visually-hidden", data: stimulus_item(target: :source_link, for: STIMULUS_CONTROLLER)
        div class: "entry-toolbar" do
          site_info
          entry_buttons
        end
      end
    end

    private

    def controller_data
      stimulus(
        controller: STIMULUS_CONTROLLER,
        values: {
          entry_id: 0,
          feed_id: 0,
          starred: "false",
          read: "false",
          extract: "false",
          loading: "false",
          pages: "false",
          subscribed: "false",
          starred_url: starred_entries_entry_path(ENTRY_ID),
          unread_url: unread_entries_entry_path(ENTRY_ID),
          extract_url: entry_extract_path(ENTRY_ID),
          delete_url: entry_path(ENTRY_ID),
          sticky_url: settings_sticky_path(FEED_ID),
          edit_subscription_url: edit_subscription_path(FEED_ID, app: true)
        },
        actions: {
          "entry-toolbar:show@window" => "show",
          "entry-toolbar:star@window" => "toggleStarred",
          "entry-toolbar:read@window" => "toggleRead",
          "entry-toolbar:extract@window" => "toggleExtract"
        }
      )
    end

    def site_info
      div class: "site-info" do
        button class: "back-button", data: {behavior: "show_entries_panel"} do
          Icon("icon-arrow")
        end
        button class: "entry-button button-full-screen", title: "Exit full screen", data: {behavior: "full_screen", toggle: "tooltip"} do
          Icon("icon-close")
        end

        # Both headers hold the favicon and the feed title; the subscribed
        # value shows one of them.
        a class: "feed-button link group-data-[entry-toolbar-subscribed-value=false]:tw-hidden", title: "Edit Subscription", data: {
          remote: "true",
          open_dialog: Dialog::EditSubscription.dom_id,
          toggle: "tooltip",
          entry_toolbar_target: "header feedLink"
        }
        span class: "feed-button group-data-[entry-toolbar-subscribed-value=true]:tw-hidden", data: stimulus_item(target: :header, for: STIMULUS_CONTROLLER)
      end
    end

    def entry_buttons
      div class: "entry-buttons" do
        div class: "entry-button-wrap group-data-[entry-toolbar-pages-value=false]:tw-hidden" do
          toolbar_button(action: :delete, class: "entry-button", title: "Delete page") do
            Icon("icon-delete")
          end
        end

        render partial("sharing_services/sharing_service_button")

        div class: "entry-button-wrap" do
          toolbar_button(action: :toggle_extract, class: "entry-button button-toggle-content", title: "Extract full content <i>c</i>") do
            Icon("icon-full-content")
            Icon("icon-full-content-on")
          end
        end

        div class: "entry-button-wrap" do
          toolbar_button(action: :toggle_starred, class: "entry-button button-toggle-starred", title: "Star <i>s</i>") do
            Icon("icon-star-on")
            Icon("icon-star-off")
          end
        end

        div class: "entry-button-wrap" do
          toolbar_button(action: :toggle_read, class: "entry-button button-toggle-read", title: "Mark as read <i>m</i>") do
            Icon("icon-read")
            Icon("icon-unread")
          end
        end

        render partial("shared/entry_settings_button")
        render partial("shared/app_settings")
      end
    end

    def toolbar_button(action:, class:, title:, &)
      data = stimulus_item(actions: {click: action}, data: {toggle: "tooltip", html: "true"}, for: STIMULUS_CONTROLLER)
      button(type: "button", class: binding.local_variable_get(:class), title:, data:, &)
    end
  end
end
