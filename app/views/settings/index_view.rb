module Settings
  class IndexView < ApplicationView

    def initialize(user:)
      @user = user
    end

    def view_template
      form_for @user, remote: true, url: helpers.settings_update_user_path(@user) do |f|
        render Settings::H1Component.new do
          "Settings"
        end

        render Settings::ControlGroupComponent.new(class: "mb-14") do |group|
          group.header do
            "Unread Sort"
          end
          group.item do
            f.radio_button(:entry_sort, "DESC", checked: @user.entry_sort.nil? || @user.entry_sort === "DESC", class: "peer", data: {behavior: "auto_submit"})
            f.label :entry_sort_desc, class: "group" do
              render Settings::ControlRowComponent.new do |row|
                row.title { "Newest First" }
                row.control { render Form::RadioComponent.new }
              end
            end
          end
          group.item do
            f.radio_button(:entry_sort, "ASC", class: "peer", data: {behavior: "auto_submit"})
            f.label :entry_sort_asc, class: "group" do
              render Settings::ControlRowComponent.new do |row|
                row.title { "Oldest First" }
                row.control { render Form::RadioComponent.new }
              end
            end
          end
        end

        render Settings::ControlGroupComponent.new(class: "mb-14") do |group|
          group.header do
            "Collections"
          end
          group.item do
            f.check_box :hide_updated, {checked: @user.hide_updated.nil? || !@user.setting_on?(:hide_updated), class: "peer", data: {behavior: "auto_submit"}}, "0", "1"
            f.label :hide_updated, class: "group" do
              render Settings::ControlRowComponent.new do |row|
                row.title { "Updated" }
                row.control { render Form::SwitchComponent.new }
              end
            end
          end
          group.item do
            f.check_box :hide_recently_read, {checked: @user.hide_recently_read.nil? || !@user.setting_on?(:hide_recently_read), class: "peer", data: {behavior: "auto_submit"}}, "0", "1"
            f.label :hide_recently_read, class: "group" do
              render Settings::ControlRowComponent.new do |row|
                row.title { "Recently Read" }
                row.control { render Form::SwitchComponent.new }
              end
            end
          end
          if @user.recently_played_entries.exists?
            group.item do
              f.check_box :hide_recently_played, {checked: @user.hide_recently_played.nil? || !@user.setting_on?(:hide_recently_played), class: "peer", data: {behavior: "auto_submit"}}, "0", "1"
              f.label :hide_recently_played, class: "group" do
                render Settings::ControlRowComponent.new do |row|
                  row.title { "Recently Played" }
                  row.control { render Form::SwitchComponent.new }
                end
              end
            end
          end
          if @user.queued_entries.exists?
            group.item do
              f.check_box :hide_airshow, {checked: @user.hide_airshow.nil? || !@user.setting_on?(:hide_airshow), class: "peer", data: {behavior: "auto_submit"}}, "0", "1"
              f.label :hide_airshow, class: "group" do
                render Settings::ControlRowComponent.new do |row|
                  row.title { "Airshow" }
                  row.control { render Form::SwitchComponent.new }
                end
              end
            end
          end
        end

        render Settings::ControlGroupComponent.new(class: "mb-14") do |group|
          group.header do
            "Features"
          end
          group.item do
            f.check_box :mark_as_read_confirmation, class: "peer", data: {behavior: "auto_submit"}
            f.label :mark_as_read_confirmation, class: "group" do
              render Settings::ControlRowComponent.new do |row|
                row.title {"Ask before marking all as read" }
                row.control { render Form::SwitchComponent.new }
              end
            end
          end
          group.item do
            f.check_box :show_unread_count, class: "peer", data: {behavior: "auto_submit"}
            f.label :show_unread_count, class: "group" do
              render Settings::ControlRowComponent.new do |row|
                row.title { "Unread count in title" }
                row.control { render Form::SwitchComponent.new }
              end
            end
          end
          group.item do
            f.check_box :sticky_view_inline, class: "peer", data: {behavior: "auto_submit"}
            f.label :sticky_view_inline, class: "group" do
              render Settings::ControlRowComponent.new do |row|
                row.title { "Sticky Full Content" }
                row.description { "Always attempt to load the full content from the original site" }
                row.control { render Form::SwitchComponent.new }
              end
            end
          end
          group.item do
            f.check_box :starred_feed_enabled, class: "peer", data: {behavior: "auto_submit"}
            f.label :starred_feed_enabled, class: "group" do
              render Settings::ControlRowComponent.new do |row|
                row.title { "Starred article feed" }
                row.description do
                  span class: "overflow-hidden", data: {behavior: "starred_feed_url"} do
                    render Shared::StarredFeedUrl.new(user: @user)
                  end
                end
                row.control { render Form::SwitchComponent.new }
              end
            end
          end
        end

        render Settings::ControlGroupComponent.new class: "mb-14" do |group|
          group.header { "Pages" }

          group.item do
            render Settings::ControlRowComponent.new do |row|
              row.title { "Bookmarklet" }

              row.description do
                plain "Drag this to your bookmarks bar. Use it to "
                a(href: "/blog/2019/08/20/save-webpages-to-read-later/") do
                  "save articles from the web"
                end
                plain " to Feedbin."
              end

              row.control do
                link_to helpers.bookmarklet, onclick: "return false;", class: "button-secondary cursor-move" do
                  render SvgComponent.new "favicon-saved", class: "fill-500"
                  plain " Send to Feedbin "
                  render SvgComponent.new "icon-grabber", class: "ml-6 fill-700"
                end
              end
            end
          end
        end

        render Settings::ControlGroupComponent.new(class: "mb-14") do |group|
          group.header do
            "Advanced"
          end
          group.item do
            f.check_box :view_links_in_app, {checked: @user.setting_on?(:view_links_in_app), class: "peer", data: {behavior: "auto_submit"}}, "1", "0"
            f.label :view_links_in_app, class: "group" do
              render Settings::ControlRowComponent.new do |row|
                row.title {"Always view links in Feedbin" }
                row.description do
                  plain "Load article links in Feedbin‘s "
                  a(href: "/blog/2017/07/25/view-links-in-feedbin/") { "link viewer" }
                  plain " by default."
                end
                row.control { render Form::SwitchComponent.new }
              end
            end
          end
          group.item do
            f.check_box :disable_image_proxy, {checked: @user.disable_image_proxy.nil? || !@user.setting_on?(:disable_image_proxy), class: "peer", data: {behavior: "auto_submit"}}, "0", "1"
            f.label :disable_image_proxy, class: "group" do
              render Settings::ControlRowComponent.new do |row|
                row.title { "Image proxy" }
                row.description do
                  plain "A TLS enabled image proxy is used to prevent "
                  a(href: "https://developer.mozilla.org/en-US/docs/Security/MixedContent") { "mixed content" }
                  plain " warnings. You can turn it off if you experience image loading issues."
                end
                row.control { render Form::SwitchComponent.new }
              end
            end
          end
        end

      end
    end
  end
end
