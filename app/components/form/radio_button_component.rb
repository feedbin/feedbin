class Form::RadioButtonComponent < BaseComponent
  def call
    content_tag :span, class: "w-[16px] h-[16px] shadow-one flex rounded-full relative mr-1 border border-400 pg-checked:border-2 pg-checked:border-blue-600 pg-active:bg-300 pg-active:border-500 pg-checked:pg-active:bg-transparent pg-checked:pg-active:border-blue-600 pg-focus:shadow-none" do
      content_tag :span, class: "absolute flex items-center justify-center -translate-x-1/2 -translate-y-1/2 left-1/2 top-1/2 w-[22px] h-[22px] rounded-full border-2 border-transparent pg-focus:border-blue-400 transition duration-200" do
        content_tag :span, "", class: "w-[8px] h-[8px] flex rounded-full bg-transparent pg-checked:bg-blue-600 transition"
      end
    end
  end
end
