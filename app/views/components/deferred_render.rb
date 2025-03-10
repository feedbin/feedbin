module DeferredRender
  def before_template(&)
  	vanish(&)
  	super
  end
end