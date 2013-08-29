class ImportUploader < CarrierWave::Uploader::Base
  include CarrierWaveDirect::Uploader
  include CarrierWave::MimeTypes
  process :set_content_type

  def extension_white_list
    %w(opml xml json)
  end
end
