module TrackableAttributes
  extend ActiveSupport::Concern

  included do
    class_attribute :tracked_attributes, instance_writer: false, default: []
    before_update :touch_attributes
    has_many :attribute_changes, as: :trackable, dependent: :delete_all
    attribute_method_suffix "_updated_at"
  end

  class_methods do
    def track(*attributes)
      self.tracked_attributes = [*attributes]
    end
  end

  def touch_attributes
    changes = []
    self.tracked_attributes.each do |attribute|
      if will_save_change_to_attribute?(attribute)
        changes.push self.attribute_changes.new(name: attribute)
      end
    end
    AttributeChange.import(changes, on_duplicate_key_update: {conflict_target: [:trackable_id, :trackable_type, :name], columns: [:updated_at]}) if changes.present?
  end

  def attribute_updated_at(attribute_name)
    attribute_changes.where(name: attribute_name).take&.updated_at || self.updated_at
  end

end