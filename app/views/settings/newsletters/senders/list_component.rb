module Settings::Newsletters::Senders
  class ListComponent < ApplicationComponent
    def initialize(user:, feed_ids:, senders:)
      @user = user
      @feed_ids = feed_ids
      @senders = senders
    end

    def view_template
      if @senders.nil?
        tabs
      else
        search_results
      end
    end

    def tabs
      render TabsComponent.new do |tabs|
        tabs.tab(title: "Allowed") do
          render ItemsView.new(user: @user, feed_ids: @feed_ids, active: true)
        end
        tabs.tab(title: "Blocked") do
          render ItemsView.new(user: @user, feed_ids: @feed_ids, active: false)
        end
      end
    end

    def search_results
      render Settings::ControlGroupComponent.new(class: "mb-14") do |group|
        if @senders.present?
          @senders.each do |sender|
            group.item do
              render SenderComponent.new(sender:, feed_ids: @feed_ids)
            end
          end
        else
          group.item do
            render Settings::ControlRowComponent.new do |row|
              row.title do
                p(class: "text-500 text-center") { "No Senders" }
              end
            end
          end
        end
      end
    end
  end

  class ItemsView < ApplicationView
    def initialize(user:, feed_ids:, active:)
      @user = user
      @feed_ids = feed_ids
      @active = active
    end

    def view_template
      @user.newsletter_addresses.each do |address|
        div class: "mb-14" do
          div class: "flex items-center pb-4" do
            div class: "grow" do
              render CopyableComponent.new(data: address.title) do
                render Settings::H2Component.new(class: "!mb-0") do
                  address.title
                end
              end

              if address.description.present?
                p(class: "text-500") { address.description }
              end
            end
            link_to "Manage", settings_newsletters_address_path(address), class: "button button-tertiary"
          end

          @senders = if @active
            address.newsletter_senders.where(feed_id: @feed_ids)
          else
            address.newsletter_senders.where.not(feed_id: @feed_ids)
          end

          render Settings::ControlGroupComponent.new(class: "mb-14") do |group|
            if @senders.exists?
              newsletter_senders(address, group)
            else
              group.item do
                render Settings::ControlRowComponent.new do |row|
                  row.title do
                    p(class: "text-500 text-center") { "No Senders" }
                  end
                end
              end
            end
          end

        end
      end
    end

    def newsletter_senders(address, group)
      @senders.each do |sender|
        group.item do
          render SenderComponent.new(sender:, feed_ids: @feed_ids)
        end
      end
    end

  end
end
