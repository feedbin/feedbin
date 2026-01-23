module Settings
  module Imports
    class ShowView < ApplicationView

      slots :header

      def initialize(import:, content_src:, onboarding: false)
        @import = import
        @onboarding = onboarding
        @content_src = content_src
      end

      def view_template
        if header?
          render &@header
        else
          render Settings::H1Component.new do
            "Import Status"
          end
          render SubtitleComponent.new do
            @import.created_at.to_formatted_s(:date)
          end
        end

        div data: @import.complete? ? {} : {content_src: @content_src} do
          render Settings::Imports::StatusComponent.new import: @import, onboarding: @onboarding
        end
      end
    end
  end
end
