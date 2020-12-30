class Embed < ApplicationRecord
  belongs_to :parent, class_name: "Embed", foreign_key: "parent_id"
  enum source: {youtube_video: 0, youtube_channel: 1}
  
  def channel
    youtube_video? && self.class.youtube_channel.find_by_provider_id(parent_id)
  end
end
