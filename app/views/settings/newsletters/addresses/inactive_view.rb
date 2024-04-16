module Settings::Newsletters::Addresses
  class InactiveView < ApplicationView
    def initialize(addresses:)
      @addresses = addresses
    end

    def view_template
      render Settings::H1Component.new do
        "Newsletters"
      end

      render Settings::ControlGroupComponent.new class: "mb-14" do |group|
        group.header { "Inactive Addresses" }

        @addresses.each do |address|
          group.item do
            form_with(model: address, url: activate_settings_newsletters_address_path(address), method: :patch) do |form|
              render Settings::ControlRowComponent.new do |row|
                row.title do
                  address.title
                end

                if address.description.present?
                  row.description do
                    address.description
                  end
                end

                row.control do
                  button class: "button button-tertiary" do
                    "Activate"
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
