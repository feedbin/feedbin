module Settings
  class ButtonRowComponent < ApplicationComponent
    def template
      div class: "flex gap-4 mt-8 justify-end" do
        yield
      end
    end
  end
end
