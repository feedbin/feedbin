module App
  class SpinnerComponent < ApplicationComponent
    def template
      div class: "flex-center w-full h-full transition opacity-0 tw-hidden group-data-[processing=true]:opacity-100 group-data-[processing=true]:flex" do
        div class: "spinner small" do

        end
      end
    end
  end
end
