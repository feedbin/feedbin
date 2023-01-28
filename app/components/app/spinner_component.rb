class App::SpinnerComponent < BaseComponent

  def call
    content_tag :div, class: "absolute right-0 inset-y-0 flex items-center pr-4 transition opacity-0 group-data-[processing=true]:opacity-100" do
      content_tag :div, "", class: "spinner small"
    end
  end

end
