module Settings
  class NewslettersPagesView < ApplicationView

    def initialize(user:, subscription_ids:)
      @user = user
      @subscription_ids = subscription_ids
    end

    def template
      render Settings::H1Component.new do
        "Newsletters"
      end

      newsletters
      newsletter_senders
    end

    def newsletters
      form_for @user, remote: true, url: settings_update_user_path(@user) do |f|
        render Settings::ControlGroupComponent.new class: "mb-14" do |group|

          group.item do
            div(class: "py-4") do
              div(class: "text-600") { " Newsletter Address" }
              div(class: "text-500 text-sm mb-2") do
                plain " Use this address to "
                a(href: "/blog/2016/02/03/subscribe-to-email-newsletters-in-feedbin/") { "receive emails" }
                plain " in Feedbin."
              end
              render Form::TextInputComponent.new do |text|
                text.input do
                  input(value: @user.newsletter_address, readonly: "readonly", class: "text-input")
                end
                text.accessory_trailing_cap do
                  button name: "button", type: "submit", data: { controller: "copyable", action: "copyable#copy", copyable_data_value: @user.newsletter_address, copyable_success_value: "false" }, class: "px-6 inset-y-0 group" do
                    span(class: "group-data-[copyable-success-value=true]:tw-hidden") { "Copy" }
                    span(class: "group-data-[copyable-success-value=false]:tw-hidden flex items-center gap-2 fill-green-600") do
                      render SvgComponent.new "icon-check"
                      plain " Copied"
                    end
                  end
                end
              end
            end
          end

          group.item do
            render Settings::ControlRowComponent.new do |row|
              row.title { "Default Tag" }

              row.description do
                "Automatically put incoming newsletters in this tag. "
              end

              row.control do
                render Form::SelectInputComponent.new do |input|
                  input.input do
                    f.select :newsletter_tag, helpers.tag_options, {}, { class: "peer", data: { behavior: "auto_submit" } }
                  end
                  input.accessory_leading do
                    render SvgComponent.new "favicon-tag", class: "fill-500"
                  end
                end
              end
            end
          end
        end
      end
    end

    def pages
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
    end

    def newsletter_senders
      if @user.newsletter_senders.exists?
        render Settings::ExpandableComponent.new do |expandable|
          expandable.header { plain " Advanced " }

          expandable.description do
            render Settings::ControlRowComponent.new do |row|
              row.title { "Newsletter Senders" }

              row.description do
                plain " These are the senders of newsletters you have received. Feedbin blocks messages from senders that have been deactivated. Reactivate a sender to resubscribe. "
              end

              row.control do
                button class: "button button-secondary", data: { action: "expandable#toggle", toggle_text: "Hide Senders" } do
                  "Show Senders"
                end
              end
            end
          end

          @user.newsletter_senders.each do |newsletter_sender|
            expandable.item do
              form_with( model: newsletter_sender, url: newsletter_senders_settings_subscription_path( newsletter_sender.feed_id ), namespace: newsletter_sender.feed_id, data: { remote: true } ) do |f|
                f.check_box :feed_id, { checked: @subscription_ids.include?( newsletter_sender.feed_id ), class: "peer", data: { behavior: "auto_submit" } }
                f.label :feed_id, class: "group" do
                  render Settings::ControlRowComponent.new do |row|
                    row.title do
                      plain newsletter_sender.name
                      whitespace
                      span(class: "text-500") do
                        newsletter_sender.email
                      end
                    end

                    if newsletter_sender.full_token != newsletter_sender.token
                      row.description do
                        plain "Sent to "
                        plain newsletter_sender.full_token
                        plain "@newsletters.feedbin.com "
                      end
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
  end
end
