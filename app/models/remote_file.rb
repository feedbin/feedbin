# The icon proxy's legacy cache. Nothing serves from it any more:
# TwitterAvatarsController answers the icons path from images rows, and
# BackfillTwitterAvatars is the last reader. The table goes once the copy is
# done.
class RemoteFile < ApplicationRecord
  store_accessor :settings, :width, :height

  def self.fingerprint(data)
    Digest::MD5.hexdigest(data)
  end

  def self.camo_url(url)
    Camo.url(url)
  end
end
