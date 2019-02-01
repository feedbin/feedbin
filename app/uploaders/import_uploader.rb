class ImportUploader < CarrierWave::Uploader::Base
  include CarrierWaveDirect::Uploader

  def extension_white_list
    %w[opml xml]
  end
end
