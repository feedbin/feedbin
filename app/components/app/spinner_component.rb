class App::SpinnerComponent < BaseComponent

  def call
    content_tag :div, class: "flex-center w-full h-full transition opacity-0 tw-hidden group-data-[processing=true]:opacity-100 group-data-[processing=true]:flex" do
      content_tag :div, "", class: "spinner small"
    end
  end

end
