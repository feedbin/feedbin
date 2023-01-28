class Form::CheckBoxComponent < BaseComponent
  def call
    content_tag :span, class: "w-[16px] h-[16px] flex items-center justify-center shadow-one relative border border-400 transition rounded-[3px] pg-checked:bg-blue-600 pg-checked:border-blue-600 pg-active:bg-300 pg-active:border-500 pg-checked:pg-active:bg-blue-700 pg-checked:pg-active:border-blue-700 pg-disabled:bg-300 pg-disabled:border-300 pg-disabled:pg-active:bg-300 pg-disabled:pg-active:border-300 pg-focus:shadow-none" do
      capture do
        concat(svg_tag "icon-check", class: "fill-transparent pg-checked:fill-white")
        concat(content_tag :span, "", class: "absolute -translate-x-1/2 -translate-y-1/2 left-1/2 top-1/2 w-[22px] h-[22px] rounded-[5px] border-2 border-transparent pg-focus:border-blue-400 transition duration-200")
      end
    end
  end
end
