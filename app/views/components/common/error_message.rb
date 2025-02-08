class Common::ErrorMessage < Phlex::HTML
  def template
    p(class: "flex items-center p-2 bg-red-200 gap-2 rounded-lg mb-4") do
      render SvgComponent.new "icon-error-message-small", class: "fill-red-600"
      span(class: "text-[rbg(var(--day-color-600))]") { yield }
    end
  end
end