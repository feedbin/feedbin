class Settings::CheckBoxComponent < BaseComponent
  def call
    content_tag :span, class: "w-[16px] h-[16px] flex bg-200 rounded-[3px] relative border-2 border-400 pg-checked:bg-green-600 pg-checked:border-green-600 pg-active:bg-300 pg-active:border-500 pg-checked:pg-active:bg-green-700 pg-checked:pg-active:border-green-700 pg-disabled:bg-300 pg-disabled:border-300 pg-disabled:pg-active:bg-300 pg-disabled:pg-active:border-300" do
      content_tag :span, class: "absolute flex items-center justify-center -translate-x-1/2 -translate-y-1/2 left-1/2 top-1/2 w-[26px] h-[26px] rounded-[8px] border-4 border-transparent pg-focus:border-blue-400" do
        svg_tag "icon-check", class: "fill-transparent pg-checked:fill-white"
      end
    end
  end
end
