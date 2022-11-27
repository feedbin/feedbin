class Form::InputAccessoryComponent < BaseComponent
  def initialize(position: nil)
    @position = position || "leading"
  end
end
