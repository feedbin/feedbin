class App::SpinnerComponent < BaseComponent

  def call
    content_tag :div, class: "flex flex-center w-full h-full transition opacity-0 group-data-[processing=true]:opacity-100" do
      content_tag :div, "", class: "spinner small"
    end
  end

end
