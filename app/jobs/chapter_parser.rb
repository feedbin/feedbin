class ChapterParser
  include Sidekiq::Worker
  sidekiq_options queue: :network_default, retry: false

  MAX_SIZE = 5.megabytes

  def perform(entry_id)
    @entry = Entry.find(entry_id)
    @url = @entry.data.safe_dig("enclosure_url")

    return if @url.nil?

    response = request
    tempfile = Tempfile.new("podcast", binmode: true)
    response.body.each do |chunk|
      tempfile.write(chunk)
      chunk.clear
      if !response[:content_range] && tempfile.size > MAX_SIZE
        break
      end
    end
    tempfile.open
    tempfile.rewind

    command = "ffprobe -i %<file>s -print_format json -show_chapters -loglevel error"
    arguments = { file: Shellwords.escape(tempfile.path) }
    out, _, status = Open3.capture3(command % arguments)
    data = JSON.load(out)
    if chapters = data.safe_dig("chapters") && chapters.count > 0
      Sidekiq.logger.info "Found chapters entry=#{@entry.id}"
      @entry.update(chapters:)
    end
  end

  def request
    @url = @entry.rebase_url(@url)
    @url = Addressable::URI.heuristic_parse(@url)

    basic_auth = {}
    basic_auth[:user] = @url.user if @url.user
    basic_auth[:pass] = @url.password if @url.user

    @url = Addressable::URI.new(scheme: @url.scheme, host: @url.host, port: @url.port, path: @url.path, query: @url.query, fragment: @url.fragment).to_s

    http= HTTP
      .follow(max_hops: 4)
      .timeout(connect: 10, write: 10, read: 30)
      .encoding(Encoding::BINARY)
      .headers(
        accept: "*/*",
        range: "bytes=0-#{MAX_SIZE}"
      )

    unless basic_auth.empty?
      http = http.basic_auth(basic_auth)
    end

    http.get(@url)
  end
end