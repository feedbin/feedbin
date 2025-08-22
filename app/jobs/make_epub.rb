class MakeEpub
  include Sidekiq::Worker

  def perform(entry_id, user_id, address, extract = false)
    @entry = Entry.find(entry_id)
    @user = User.find(user_id)
    @address = address
    @extract = extract
    build
  end

  def build
    @subscription = @user.subscriptions.where(feed: @entry.feed).take
    @feed_title = @subscription&.title || @entry.feed.title
    @content = select_content
    @directory = Dir.mktmpdir
    @image_path = File.join(@directory, "OEBPS", "images")
    @images = []

    FileUtils.mkdir File.join(@directory, "META-INF")
    FileUtils.mkdir File.join(@directory, "OEBPS")
    FileUtils.mkdir @image_path

    epub_path = File.join(Dir.tmpdir, "#{SecureRandom.hex}.epub")

    @cover = generate_cover

    write_file(path: ["OEBPS", "article.xhtml"], content: formatted_content)
    write_file(path: ["mimetype"], content: "application/epub+zip")

    render_to_file(
      path: ["OEBPS", "package.opf"],
      template: "epub/package",
      formats: :xml,
      locals: {feed_title: @feed_title, entry: @content, images: @images, cover: @cover}
    )

    render_to_file(
      path: ["OEBPS", "toc.xhtml"],
      template: "epub/toc",
      formats: :html,
      locals: {entry: @content}
    )

    render_to_file(
      path: ["OEBPS", "css.css"],
      template: "epub/css",
      formats: :css
    )

    render_to_file(
      path: ["META-INF", "container.xml"],
      template: "epub/container",
      formats: :xml
    )

    mimetype = "mimetype"
    ::Zip::File.open(epub_path, ::Zip::File::CREATE) do |zip_file|
      # mimetype goes first, uncompressed
      zip_file.add_stored(mimetype, File.join(@directory, mimetype))
      Dir[File.join(@directory, "**", "**")].each do |file|
        relative_path = Pathname.new(file).relative_path_from(@directory).to_s
        next if relative_path == mimetype
        zip_file.add(relative_path, file)
      end
    end

    UserMailer.kindle(@address, @content.title.to_plain_text, epub_path).deliver_now
  ensure
    FileUtils.remove_entry(@directory)
    FileUtils.remove_entry(epub_path) rescue Errno::ENOENT
  end

  def select_content
    content = @entry
    if @extract
      content = MercuryParser.parse(@entry.fully_qualified_url) rescue content
      @feed_title = content&.domain || @feed_title
    end
    content
  end

  def render_to_file(path:, template:, formats:, locals: {})
    write_file(
      path: path,
      content: ApplicationController.render(template: template, formats: formats, locals: locals, layout: nil)
    )
  end

  def write_file(path:, content:)
    File.write(File.join(@directory, *path), content)
  end

  def formatted_content
    content = ApplicationController.render(Epub::ArticleView.new(entry: @content, source: @feed_title), layout: nil)
    document = Nokogiri::HTML5(content)

    # max size for a postmark email is 10MB
    max_size = 9.megabytes
    document.css("img").each do |image|
      src = image["src"]
      if src.nil? || !src.start_with?("http")
        image.remove
        next
      end

      if file = download(src)
        unless @images.find { _1.filename == file.filename }
          total_size = @images.sum(&:size) + file.size
          break if total_size > max_size
          @images.push(file)
        end
        image["src"] = "images/#{file.filename}"
      else
        image.remove
      end
    end

    document.to_xhtml
  end

  def generate_cover
    canvas = Vips::Image.new_from_file(Rails.root.join("app", "views", "epub", "background.png").to_s)

    margin = 120
    title_text = text_layer(
      format_text(@content.title, 120),
      width: canvas.width - (margin * 2),
      opacity: 0.8,
      font: "Helvetica Bold 16"
    )

    title_y = 400 + margin
    canvas = canvas.composite(title_text, :over, x: margin, y: title_y)

    subtitle_y = title_y + title_text.height + 120

    subtitle = [@content.author, @feed_title].compact.map { format_text(_1, 25) }.join(", ")
    subtitle_text = text_layer(
      subtitle,
      width: canvas.width - (margin * 2),
      opacity: 0.5,
      font: "Helvetica 16"
    )

    canvas = canvas.composite(subtitle_text, :over, x: margin, y: subtitle_y)

    canvas.write_to_file(File.join(@directory, "OEBPS", "cover.png"))

    true
  rescue => exception
    ErrorService.notify(exception, context: {entry_id: @entry.id})
    nil
  end

  def text_layer(text, width:, opacity:, font:)
    image = Vips::Image.text(
      text,
      font: font,
      width: width,
      dpi: 600,
      rgba: true,
      spacing: 24
    )
    transparency = image.new_from_image([0, 0, 0, 255 * opacity])
    image.ifthenelse(transparency, [0, 0, 0, 0], blend: true)
  end

  def format_text(text, limit)
    HTMLEntities.new.encode(text.to_plain_text.truncate(limit, separator: " ", omission: "…"), :basic)
  end

  def download(src)
    file = Download.new(src, @image_path)
    file.download
    return nil unless file.content_type =~ /image/i
    file
  rescue
    nil
  end
end