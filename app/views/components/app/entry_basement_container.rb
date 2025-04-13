module App
  class EntryBasementContainer < ApplicationComponent
    def initialize(target:)
      @target = target
    end

    def view_template
      div class: "basement-panel hide", data_basement_panel_target: @target do
        div class: "py-6 px-8" do
          div class: "max-w-[620px] mx-auto", data_behavior: "share_form" do
            yield
          end
        end
      end
    end
  end
end
