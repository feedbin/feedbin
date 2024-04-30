module SettingsNav
  class HeaderComponent < ApplicationComponent
    def view_template(&)
      div(class: "mt-8 mb-4 font-bold text-700 group-data-[nav=dropdown]:hidden group-data-[nav=modal]:mt-4", &)
    end
  end
end
