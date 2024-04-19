module Settings::Newsletters::Senders
  class IndexView < ApplicationView
    def initialize(user:, feed_ids:, senders:)
      @user = user
      @feed_ids = feed_ids
      @senders = senders
    end

    def view_template
      render Settings::H1Component.new do
        "Newsletter Senders"
      end

      form_tag helpers.settings_newsletters_senders_path, method: :get, remote: true, data: {behavior: "spinner"} do
        div class: "mb-6" do
          render Form::TextInputComponent.new do |text|
            text.input do
              input(
                type: "search",
                class: "peer text-input",
                placeholder: "Search Senders",
                data_behavior: "autosubmit",
                name: "q",
                value: helpers.params[:q],
                autocomplete: "off",
                autocorrect: "off",
                autocapitalize: "off",
                spellcheck: "false"
              )
            end
            text.accessory_leading do
              render SvgComponent.new "icon-search", class: "fill-400 pg-focus:fill-blue-600"
            end
          end
        end
      end

      div data_behavior: "senders_list" do
        render Settings::Newsletters::Senders::ListComponent.new(user: @user, feed_ids: @feed_ids, senders: @senders)
      end
    end
  end
end
