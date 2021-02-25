module Helpers
  def copy_image(url)
    url = URI.parse(url)
    source_object_name = url.path[1..-1]

    S3_POOL.with do |connection|
      connection.copy_object(ENV['AWS_S3_BUCKET'], source_object_name, ENV['AWS_S3_BUCKET'], path, options)
    end
    final_url = url.path = "/#{path}"
    url.to_s
  end

  def path
    @path ||= begin
      File.join(@public_id[0..6], "#{@public_id}.jpg")
    end
  end

  def options
    {
      "Cache-Control" => "max-age=315360000, public",
      "Expires" => "Sun, 29 Jun 2036 17:48:34 GMT",
      "x-amz-storage-class" => ENV["AWS_S3_STORAGE_CLASS"] || "REDUCED_REDUNDANCY" 
    }
  end

end
