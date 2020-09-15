class Download
  attr_reader :url, :response

  def initialize(url)
    @url = url
  end

  def filename
    @filename ||= key + extension
  end

  def path
    @path ||= "#{key[0..2]}/#{filename}"
  end

  def file_path
    @file_path ||= Pathname.new(File.join(Dir.tmpdir, SecureRandom.hex))
  end

  def download
    File.open(file_path, "wb") do |f|
      @response = HTTP.timeout(write: 5, connect: 5, read: 20).follow(max_hops: 5).get(url)
      @response.body.each { |chunk| f.write(chunk) }
    end
    file_path
  end

  def delete
    File.delete(file_path) if File.exist?(file_path)
  end

  def content_type
    response&.mime_type
  end

  private

  def extension
    @extension ||= File.extname url
  end

  def key
    @key ||= Digest::SHA1.hexdigest url
  end
end
