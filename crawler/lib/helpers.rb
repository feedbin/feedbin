module Helpers
  def preset
    OpenStruct.new(IMAGE_PRESETS[@preset_name.to_sym])
  end

  def send_to_feedbin(original_url:, storage_url:)
    Sidekiq::Client.push(
      "args"  => [@public_id, {
        "original_url"  => original_url,
        "processed_url" => storage_url,
        "width"         => preset.width,
        "height"        => preset.height
      }],
      "class" => preset.job_class,
      "queue" => "default"
    )
  end

  def image_name
    File.join(@public_id[0..6], "#{@public_id}.jpg")
  end

  def storage_options
    {
      "Cache-Control"       => "max-age=315360000, public",
      "Expires"             => "Sun, 29 Jun 2036 17:48:34 GMT",
      "x-amz-storage-class" => ENV["AWS_S3_STORAGE_CLASS"] || "REDUCED_REDUNDANCY",
      "x-amz-acl"           => "public-read"
    }
  end
end
