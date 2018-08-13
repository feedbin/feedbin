class StarredExportUploader < CarrierWave::Uploader::Base
  storage :fog

  def store_dir
    "starred_export"
  end

  def fog_public
    false
  end

  def fog_authenticated_url_expiration
    24.hours
  end

  def fog_attributes
    {
      "Content-Disposition" => "attachment; filename=starred.json",
    }
  end
end
