class ImageTag < ApplicationRecord
  belongs_to :image
  belongs_to :imageable, polymorphic: true
end
