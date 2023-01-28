class Form::InputCapComponent < BaseComponent
  def initialize(position: nil)
    @position = position || "leading"
  end
end
