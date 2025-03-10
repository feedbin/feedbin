module Settings::Newsletters::Addresses
  class NewView < ApplicationView
    def initialize(user:)
      @user = user
    end

    def view_template
      form_with(model: AuthenticationToken.new, url: settings_newsletters_addresses_path, data: { remote: true, behavior: "disable_on_submit" }) do |form|
        form.hidden_field :verified_token
        render Settings::H1Component.new do
          "Newsletters"
        end
        render App::ExpandableContainerComponent.new(open: true) do |expandable|
          render Settings::ControlGroupComponent.new do |group|
            group.header do
              "New Address"
            end
            group.item do
              form.radio_button(:type, "custom", checked: true, class: "peer", data: stimulus_item(actions: {change: :toggle}, params: {toggle_target: true}, data: {behavior: "auto_submit"}, for: :expandable))
              form.label :type_custom, class: "group" do
                render Settings::ControlRowComponent.new do |row|
                  row.title { "Custom" }
                  row.description {"Customize your address."}
                  row.control { render Form::RadioComponent.new }
                end
              end
              expandable.content do
                div class: "pb-4" do
                  render Form::TextInputComponent.new do |text|
                    text.input do
                      form.text_field :token, data: {behavior: "autosubmit"}, autocomplete: "off", autocorrect: "off", autocapitalize: "off", spellcheck: "false"
                    end
                    text.accessory_leading do
                      Icon("favicon-newsletter", class: "ml-2 fill-400 pg-focus:fill-blue-600")
                    end
                    text.accessory_trailing do
                      div class: "flex h-full", data: {behavior: "token_suffix"} do
                      end
                    end
                  end
                  div data: {behavior: "token_message"} do
                    render MessageComponent.new
                  end
                end
              end
            end
            group.item do
              form.radio_button(:type, "random", class: "peer", data: stimulus_item(actions: {change: :toggle}, data: {behavior: "auto_submit"}, for: :expandable))
              form.label :type_random, class: "group" do
                render Settings::ControlRowComponent.new do |row|
                  row.title { "Random" }
                  row.description {"Randomly generated unique address."}
                  row.control { render Form::RadioComponent.new }
                end
              end
            end
          end
        end

        render Settings::ButtonRowComponent.new do
          button class: "button", type: "submit", name: "button_action", value: "save", disabled: true do
            "Create"
          end
        end

      end
    end

    class TokenSuffixComponent < ApplicationComponent
      def initialize(suffix:)
        @suffix = suffix
      end

      def view_template
        span class: "bg-100 border-l border-300 text-400 rounded-r-[5px] flex flex-center w-[75px] h-full" do
          plain @suffix
        end
      end
    end

    class MessageComponent < ApplicationComponent
      def initialize(address: nil)
        @address = address
      end

      def view_template
        div(class: "text-500 text-sm pt-2 break-all") do
          if @address.present?
            "#{@address}@#{ENV["NEWSLETTER_ADDRESS_HOST"]}"
          else
            "Choose a custom prefix."
          end
        end
      end
    end
  end
end
