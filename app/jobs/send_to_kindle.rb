class SendToKindle
  include Sidekiq::Worker
  sidekiq_options queue: :critical
  SUPPORTED_IMAGES = %w[.jpg .jpeg .gif .png .bmp]

  def perform(entry_id, kindle_address)
    if ENV["KINDLEGEN_PATH"].blank?
      Rails.logger.error { 'Missing ENV["KINDLEGEN_PATH"]' }
    else
      send_to_kindle(entry_id, kindle_address)
    end
  end

  def send_to_kindle(entry_id, kindle_address)
    @entry = Entry.find(entry_id)
    @working_directory = Dir.mktmpdir
    begin
      content_path = write_html
      mobi_path = kindlegen(content_path)
      if File.file?(mobi_path)
        UserMailer.kindle(kindle_address, mobi_path).deliver_now
      else
        # Notify user of error?
      end
    ensure
      FileUtils.remove_entry(@working_directory)
    end
  end

  def kindlegen(content_path)
    mobi_file = "kindle.mobi"
    system("#{ENV["KINDLEGEN_PATH"]} #{content_path} -o #{mobi_file} > /dev/null")
    File.join(@working_directory, mobi_file)
  end

  def download_image(url, destination)
    File.open(destination, "wb") do |file|
      file.write(HTTParty.get(url, {timeout: 20}).parsed_response)
    end
  rescue
    false
  end

  def render_content(content)
    ApplicationController.render template: "supported_sharing_services/kindle_content.html.erb", locals: {entry: @entry, content: content}, layout: nil
  end

  def write_html
    content = ContentFormatter.api_format(@entry.content, @entry)
    content = Nokogiri::HTML.fragment(content)
    content = prepare_images(content)
    content_path = file_destination("kindle.html")
    File.open(content_path, "w") do |file|
      file.write(render_content(content.to_xml))
    end
    content_path
  end

  def prepare_images(parsed_content)
    images = []
    parsed_content.search("img").each_with_index do |element, index|
      next if element["src"].blank?
      src = element["src"].strip
      extension = File.extname(src)
      if SUPPORTED_IMAGES.include?(extension)
        filename = index.to_s + extension
        destination = file_destination(filename)
        if download_image(src, destination)
          element["src"] = filename
        end
      else
        next
      end
    end
    parsed_content
  end

  def file_destination(filename)
    File.join(@working_directory, filename)
  end
end
