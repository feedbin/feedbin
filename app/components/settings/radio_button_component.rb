class Settings::RadioButtonComponent < Settings::ControlRowComponent
  def control
    container = %w[
      w-[18px] h-[18px] flex bg-200 rounded-full relative mr-1 border-2 border-400
      pg-checked:bg-transparent pg-checked:border-green-600
      pg-active:bg-300 pg-active:border-500
      pg-checked:pg-active:bg-transparent pg-checked:pg-active:border-green-600
    ]

    ring = %w[
      absolute flex items-center justify-center -translate-x-1/2 -translate-y-1/2
      left-1/2 top-1/2 w-[28px] h-[28px] rounded-full border-4 border-transparent
      pg-focus:border-blue-400
    ]

    dot = %w[
      w-[8px] h-[8px] flex rounded-full pg-checked:bg-green-600
    ]

    content_tag :span, class: container do
      content_tag :span, class: ring do
        content_tag :span, "", class: dot
      end
    end
  end

end
