class Settings::SwitchComponent < Settings::ControlRowComponent
  def control
    content_tag :span, class: "w-[43px] h-[24px] flex bg-400 rounded-full relative pg-checked:bg-green-600 pg-active:pg-checked:bg-green-700" do
      content_tag :span, class: "absolute flex items-center justify-start -translate-x-1/2 -translate-y-1/2 left-1/2 top-1/2 w-[53px] h-[34px] rounded-full border-4 border-transparent pg-focus:border-blue-400" do
        content_tag :span, class: "w-[18px] h-[18px] flex rounded-full bg-light-100 ml-[4px] relative translate-x-0 items-center justify-center transition pg-checked:bg-white pg-checked:translate-x-[19px] shadow-md pg-active:bg-white" do
          svg_tag "icon-check", class: "absolute fill-green-600 opacity-0 transition overflow-visible pg-checked:opacity-100 pg-active:pg-checked:fill-green-700"
        end
      end
    end
  end
end
