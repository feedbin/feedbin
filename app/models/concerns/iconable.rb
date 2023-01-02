module Iconable
  extend ActiveSupport::Concern

  included do
    enum provider: {twitter: 0, youtube: 1, favicon: 2}, _prefix: true
    has_many :icons, foreign_key: "provider_id", primary_key: "provider_parent_id"
  end
end