class Common::ErrorMessage < ApplicationComponent
  def view_template
    p(class: "flex items-center p-2 bg-red-200 gap-2 rounded-lg mb-4") do
      Icon("icon-error-message-small", class: "fill-red-600")
      span(class: "text-day-600") { yield }
    end
  end
end