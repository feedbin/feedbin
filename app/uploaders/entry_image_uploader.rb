class EntryImageUploader < CarrierWave::Uploader::Base

  storage :fog

  def store_dir
    "public-images"
  end

end
