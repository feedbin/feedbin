module ImageCrawler
  module Helpers
    AWS_S3_BUCKET_IMAGES = ENV["AWS_S3_BUCKET_IMAGES"] || ENV["AWS_S3_BUCKET"]
    CASCADE = Rails.root.join("lib/cascade/facefinder")
    PIGO = ENV["PIGO_PATH"] || `which pigo`.chomp
    puts "Pigo missing. Add it to your path or set ENV['PIGO_PATH']. From https://github.com/esimov/pigo" unless File.executable?(PIGO)

    STORAGE_OPTIONS = {
      provider: "AWS",
      aws_access_key_id: ENV["AWS_ACCESS_KEY_ID"],
      aws_secret_access_key: ENV["AWS_SECRET_ACCESS_KEY"]
    }
    STORAGE_OPTIONS[:region] = ENV["AWS_S3_REGION"] if ENV["AWS_S3_REGION"]
    STORAGE_OPTIONS[:host] = ENV["AWS_S3_HOST"] if ENV["AWS_S3_HOST"]
    STORAGE_OPTIONS[:endpoint] = ENV["AWS_S3_ENDPOINT"] if ENV["AWS_S3_ENDPOINT"]
    STORAGE_OPTIONS[:path_style] = ENV["AWS_S3_PATH_STYLE"] if ENV["AWS_S3_PATH_STYLE"]

    IMAGE_PRESETS = {
      primary: {
        width: 542,
        height: 304,
        minimum_size: 20_000,
        crop: :smart_crop,
        job_class: "EntryImage"
      },
      twitter: {
        width: 542,
        height: 304,
        minimum_size: 10_000,
        crop: :smart_crop,
        job_class: "TwitterLinkImage"
      },
      youtube: {
        width: 542,
        height: 304,
        minimum_size: nil,
        crop: :fill_crop,
        job_class: "EntryImage"
      },
      podcast: {
        width: 200,
        height: 200,
        minimum_size: nil,
        crop: :fill_crop,
        job_class: "ItunesImage"
      },
      podcast_feed: {
        width: 200,
        height: 200,
        minimum_size: nil,
        crop: :fill_crop,
        job_class: "ItunesFeedImage"
      }
    }

    def preset
      OpenStruct.new(IMAGE_PRESETS[@preset_name.to_sym])
    end

    def send_to_feedbin(original_url:, storage_url:)
      Sidekiq::Client.push(
        "args" => [@public_id, {
          "original_url" => original_url,
          "processed_url" => storage_url,
          "width" => preset.width,
          "height" => preset.height
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
        "Cache-Control" => "max-age=315360000, public",
        "Expires" => "Sun, 29 Jun 2036 17:48:34 GMT",
        "x-amz-storage-class" => ENV["AWS_S3_STORAGE_CLASS"] || "REDUCED_REDUNDANCY",
        "x-amz-acl" => "public-read"
      }
    end
  end
end