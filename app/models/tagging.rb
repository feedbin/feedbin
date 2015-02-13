class Tagging < ActiveRecord::Base
  belongs_to :tag
  belongs_to :feed
  belongs_to :user
end
