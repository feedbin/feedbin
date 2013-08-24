class SharingService < ActiveRecord::Base
  belongs_to :user
  default_scope { order('lower(label)') }
end
