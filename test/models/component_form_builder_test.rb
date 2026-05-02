require "test_helper"

class ComponentFormBuilderTest < ActiveSupport::TestCase
  test "radio_button adds the peer class to options" do
    helper = Class.new(ActionView::Base) do
      include ActionView::Helpers::FormBuilder.instance_method(:object).source_location.first.then { |_| Module.new }
    end.new(ActionView::LookupContext.new([]), {}, nil)

    object = OpenStruct.new(color: "red")
    template = ActionView::Base.with_empty_template_cache.new(ActionView::LookupContext.new([]), {}, nil)
    builder = ComponentFormBuilder.new(:thing, object, template, {})

    html = builder.radio_button(:color, "blue")
    assert_includes html, "peer"
  end

  test "radio_button preserves the existing class option" do
    object = OpenStruct.new(color: "red")
    template = ActionView::Base.with_empty_template_cache.new(ActionView::LookupContext.new([]), {}, nil)
    builder = ComponentFormBuilder.new(:thing, object, template, {})

    html = builder.radio_button(:color, "blue", class: "existing-class")
    assert_includes html, "existing-class"
    assert_includes html, "peer"
  end
end
