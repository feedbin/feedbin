class BasePresenter
  
  def initialize(object, locals, template)
    @object = object
    @locals = locals
    @template = template
  end

  private

  def self.presents(name)
    define_method(name) do
      @object
    end
  end
  
end