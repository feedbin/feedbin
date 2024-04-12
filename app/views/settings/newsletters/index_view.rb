module Settings
  module Newsletters
    class IndexView < ApplicationView

      def initialize(user:, subscription_ids:)
        @user = user
        @subscription_ids = subscription_ids
      end

      def template
        render Settings::H1Component.new do
          "Newsletters"
        end

        p class: "text-500 mb-8" do
          plain "Use your Feedbin newsletter address to "
          a(href: "/blog/2016/02/03/subscribe-to-email-newsletters-in-feedbin/") { "receive email newsletters" }
          plain " right along side your feeds. Create multiple addresses to help differentiate senders and prevent unwanted messages."
        end

        senders
        addresses
      end

      def senders
        render Settings::ControlGroupComponent.new class: "mb-14" do |group|
          group.header { "General" }
          group.item do
            render Settings::ControlRowComponent.new do |row|
              row.title { "Newsletter Senders" }

              row.description do
                "Manage who can send newsletters to you."
              end

              row.control do
                link_to "Manage", settings_newsletters_senders_path, class: "button button-tertiary"
              end
            end
          end

          if @user.inactive_newsletter_addresses.exists?
            group.item do
              render Settings::ControlRowComponent.new do |row|
                row.title { "Inactive Addresses" }

                row.description do
                  "View deactivated newsletter addresses."
                end

                row.control do
                  link_to "View", inactive_settings_newsletters_addresses_path, class: "button button-tertiary"
                end
              end
            end
          end
        end
      end

      def addresses
        render Settings::ControlGroupComponent.new class: "mb-14" do |group|
          group.custom_header do
            div class: "flex items-center mb-4" do
              div class: "grow" do
                render H2Component.new(class: "!mb-0") do
                  "Addresses"
                end
              end
              link_to "New Address", new_settings_newsletters_address_path, class: "button button-secondary"
            end
          end

          @user.newsletter_addresses.order(token: :asc).each do |address|
            group.item do
              render Settings::ControlRowComponent.new do |row|
                row.title do
                  render CopyableComponent.new(data: address.title) {address.title}
                end

                if address.description.present?
                  row.description do
                    address.description
                  end
                end

                row.control do
                  link_to "Manage", settings_newsletters_address_path(address), class: "button button-tertiary"
                end
              end
            end
          end
        end
      end
    end
  end
end
