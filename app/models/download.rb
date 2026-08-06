class Download
  attr_reader :url, :response

  def initialize(url, directory = nil)
    @url = url
    @directory = directory
  end

  def filename
    @filename ||= key + extension
  end

  def path
    @path ||= "#{key[0..2]}/#{filename}"
  end

  def file_path
    @file_path ||= Pathname.new(File.join(@directory || Dir.tmpdir, local_filename))
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

  def size
    File.size file_path
  end

  private

  # `filename` is a pure function of the url, which is what the remote storage
  # path wants and what a caller that supplies its own directory wants -- it
  # links to the file by that name afterwards. In the shared process tmpdir it
  # is the wrong name: every job downloading that url computes the same
  # absolute path, and `download` truncates while `delete` unlinks, so they
  # corrupt and remove each other's files. Own the temp dir, own the name.
  def local_filename
    @local_filename ||= @directory ? filename : "#{key}-#{SecureRandom.hex}#{extension}"
  end

  def extension
    @extension ||= File.extname parsed_url.path
  end

  # Addressable rather than URI: `url` is an <img src> lifted verbatim out of
  # entry content, and URI.parse implements RFC 3986 strictly enough to reject
  # things browsers accept without complaint -- an unescaped space in a
  # filename, a scheme with no authority. Both start with "http", so both clear
  # the only filter ImageSaver applies before handing them here.
  def parsed_url
    Addressable::URI.parse url
  end

  def key
    @key ||= Digest::SHA1.hexdigest url
  end
end
