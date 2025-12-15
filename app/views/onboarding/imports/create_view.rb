module Onboarding
  module Imports
    class CreateView < ApplicationComponent
      def initialize(import:)
        @import = import
      end

      def view_template
        render Settings::Imports::ShowView.new(import: @import) do |view|
          view.header do
            div class: "pb-4" do
              div class: "text-xl font-bold" do
                "Import Status"
              end
            end
          end
        end
      end
    end
  end
end
