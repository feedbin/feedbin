module Onboarding
  module Imports
    class CreateView < ApplicationComponent
      def initialize(import:)
        @import = import
      end

      def view_template
        render Settings::Imports::ShowView.new(import: @import, content_src: onboarding_import_path(@import), onboarding: true) do |view|
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
