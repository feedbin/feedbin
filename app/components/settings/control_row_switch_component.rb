class Settings::ControlRowSwitchComponent < Settings::ControlRowComponent
  def control
    render(Form::SwitchComponent.new)
  end
end
