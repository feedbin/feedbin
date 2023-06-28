module Form
  class SwitchComponent < ApplicationComponent
    def template(&)
      span class: "w-[34px] h-[20px] flex bg-400 rounded-full relative transition duration-200 pg-checked:bg-blue-600 pg-active:pg-checked:bg-blue-700" do
        span class: "absolute flex items-center justify-start -translate-x-1/2 -translate-y-1/2 left-1/2 top-1/2 w-[40px] h-[26px] rounded-full border-2 border-transparent pg-focus:border-blue-400 group-data-[focused]:border-blue-400 transition duration-200" do
          span class: "w-[16px] h-[16px] scale-[0.875] flex rounded-full bg-light-100 ml-[2px] relative translate-x-0 items-center justify-center transition pg-checked:scale-100 pg-checked:bg-white pg-checked:translate-x-[15px] shadow-md pg-active:bg-white" do
            render SvgComponent.new "icon-check", class: "absolute fill-light-100 transition overflow-visible pg-checked:opacity-100 pg-checked:fill-blue-700 pg-active:pg-checked:fill-blue-700"
          end
        end
      end
    end
  end
end