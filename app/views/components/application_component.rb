# frozen_string_literal: true

class ApplicationComponent < Phlex::HTML
  include Phlex::Rails::Helpers::CheckBoxTag
  include Phlex::Rails::Helpers::SearchFieldTag
  include Phlex::Rails::Helpers::FieldsFor
  include Phlex::Rails::Helpers::FormFor
  include Phlex::Rails::Helpers::FormTag
  include Phlex::Rails::Helpers::FormWith
  include Phlex::Rails::Helpers::HiddenFieldTag
  include Phlex::Rails::Helpers::LinkTo
  include Phlex::Rails::Helpers::OptionsForSelect
  include Phlex::Rails::Helpers::RadioButton
  include Phlex::Rails::Helpers::Routes
  include Phlex::Rails::Helpers::SelectTag
  include Phlex::Rails::Helpers::TextFieldTag
  include Phlex::Rails::Helpers::SubmitTag
  include Phlex::Rails::Helpers::LabelTag
  include Phlex::Rails::Helpers::CollectionCheckBoxes

  include Common

  def self.slots(*items)
    include Phlex::DeferredRender
    items.each do |item|
      define_method item.to_sym, -> (&block) { instance_variable_set("@#{item.to_s}", block) }
      define_method "#{item}?".to_sym, -> (&block) { instance_variable_get("@#{item.to_s}").present? }
    end
  end

  def stimulus(controller:, actions: {}, values: {}, outlets: {}, classes: {}, data: {})
    stimulus_controller = controller.to_s.dasherize

    action = actions.map do |event, function|
      "#{event}->#{stimulus_controller}##{function.camelize(:lower)}"
    end.join(" ").presence

    values.transform_keys! do |key|
      [controller, key, "value"].join("_").to_sym
    end

    outlets.transform_keys! do |key|
      [controller, key, "outlet"].join("_").to_sym
    end

    classes.transform_keys! do |key|
      [controller, key, "class"].join("_").to_sym
    end

    { controller: stimulus_controller, action: }.merge!({ **values, **outlets, **classes, **data})
  end

  def stimulus_item(target: nil, actions: {}, params: {}, data: {}, for:)
    stimulus_controller = binding.local_variable_get(:for).to_s.dasherize

    action = actions.map do |event, function|
      "#{event}->#{stimulus_controller}##{function.to_s.camelize(:lower)}"
    end.join(" ").presence

    params.transform_keys! do |key|
      :"#{binding.local_variable_get(:for)}_#{key}_param"
    end

    defaults = { **params, **data }

    if action
      defaults[:action] = action
    end

    if target
      defaults[:"#{binding.local_variable_get(:for)}_target"] = target.to_s.camelize(:lower)
    end

    defaults
  end

  def multi_stimulus(items)
    action = []
    attributes = items.each_with_object({}) do |(key, value), hash|
      item = stimulus_item(target: value.fetch(:target, nil), actions: value.fetch(:actions, {}), params: value.fetch(:params, {}), data: value.fetch(:data, {}), for: key)
      action.push(item.delete(:action))
      hash.merge!(item)
    end
    action = action.compact.join(" ")
    if action.present?
      attributes[:action] = action
    end
    attributes
  end

  if Rails.env.development?
    def before_template
      comment { "Start: #{self.class.name}" }
      super
    end

    def after_template
      comment { "End: #{self.class.name}" }
      super
    end
  end
end
