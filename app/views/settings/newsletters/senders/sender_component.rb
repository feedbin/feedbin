module Settings::Newsletters::Senders
  class SenderComponent < ApplicationComponent
    def initialize(sender:, feed_ids:)
      @sender = sender
      @feed_ids = feed_ids
    end

    def template
      form_with(model: @sender, url: settings_newsletters_sender_path(@sender), namespace: @sender.id, data: { remote: true } ) do |f|
        f.hidden_field :token
        f.check_box :active, { checked: @feed_ids.include?(@sender.feed_id), class: "peer", data: { behavior: "auto_submit" } }
        f.label :active, class: "group" do
          render Settings::ControlRowComponent.new do |row|
            row.title do
              plain @sender.name
              whitespace
              span(class: @sender.name.present? ? "text-500" : "") do
                @sender.email
              end
            end

            row.control { render Form::SwitchComponent.new }
          end
        end
      end
    end
  end
end
