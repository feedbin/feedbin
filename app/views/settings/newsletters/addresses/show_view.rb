module Settings
  module Newsletters
    module Addresses
      class ShowView < ApplicationView

        def initialize(address:)
          @address = address
        end

        def view_template
          form_with(model: @address, url: settings_newsletters_address_path(@address), data: {remote: true}) do |form|

            render H1Component.new do
              "Newsletters"
            end
            render SubtitleComponent.new do
              render CopyableComponent.new(data: @address.title) {@address.title}
            end

            div class: "mb-14" do
              render Form::TextInputComponent.new do |text|
                text.input do
                  form.text_field :description, placeholder: "Description", class: "peer text-input", data: {behavior: "autosubmit"}
                end
              end
            end

            render Settings::ControlGroupComponent.new class: "mb-14" do |group|
              group.item do
                render Settings::ControlRowComponent.new do |row|
                  row.title { "Default Tag" }

                  row.description do
                    "Automatically put incoming newsletters in this tag. "
                  end

                  row.control do
                    render Form::SelectInputComponent.new do |input|
                      input.input do
                        form.select :newsletter_tag, tag_options, {}, { class: "peer", data: { behavior: "auto_submit" } }
                      end
                      input.accessory_leading do
                        Icon("favicon-tag", class: "fill-500")
                      end
                    end
                  end
                end
              end

              group.item do
                render Settings::ControlRowComponent.new do |row|
                  row.title { "Newsletter Senders" }

                  row.description do
                    "Manage who can send newsletters to this address."
                  end

                  row.control do
                    link_to "Manage", settings_newsletters_senders_path(q: "to:#{@address.title}"), class: "button button-tertiary"
                  end
                end
              end
            end
          end

          form_with(model: @address, url: settings_newsletters_address_path(@address), method: :delete) do |form|
            render Settings::ControlGroupComponent.new class: "mb-14" do |group|
              group.header { "Advanced" }
              group.item do
                render Settings::ControlRowComponent.new do |row|
                  row.title { "Deactivate Address" }

                  row.description do
                    "If you’re receiving unwanted messages, you can disable this address entirely. This will prevent all deliveries, and you will need to resubscribe to any newsletters you still want."
                  end

                  row.control do
                    button class: "button button-secondary", data: { confirm: 'Are you sure you want to deactivate this address?' } do
                      "Deactivate"
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
end
