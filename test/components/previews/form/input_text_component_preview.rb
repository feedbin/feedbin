class Form::InputTextComponentPreview < Lookbook::Preview
  # @param leading_accessory toggle
  def default(leading_accessory: false)
    render_with_template(locals: {
      leading_accessory: leading_accessory
    })
  end
end
