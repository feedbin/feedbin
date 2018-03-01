module Helpers
  def copy_image(url)
    url = URI.parse(url)
    source_object_name = url.path[1..-1]
    target_object_name = File.join(@public_id[0..6], "#{@public_id}.jpg")
    S3_POOL.with do |connection|
      connection.copy_object(ENV['AWS_S3_BUCKET'], source_object_name, ENV['AWS_S3_BUCKET'], target_object_name, options = {})
      connection.copy_object(ENV['AWS_S3_BUCKET'], source_object_name, ENV['AWS_S3_BUCKET_NEW'], target_object_name, options = {})
    end

    final_url = url.path = "/#{target_object_name}"
    url.to_s
  end
end