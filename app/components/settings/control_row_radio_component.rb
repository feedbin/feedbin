class Settings::ControlRowRadioComponent < Settings::ControlRowComponent
  def control
    render(Form::RadioButtonComponent.new)
  end
end
