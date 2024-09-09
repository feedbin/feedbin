xml.instruct!
xml.package "xmlns" => "http://www.idpf.org/2007/opf", "version" => "3.0", "unique-identifier" => "pub-id" do
  xml.metadata "xmlns:dc" => "http://purl.org/dc/elements/1.1/" do
    xml.dc :title, entry.title.to_plain_text
    xml.dc :creator, entry.author ? "#{entry.author}, #{feed_title}" : feed_title
    xml.dc :language, "en"
    xml.dc :identifier, "en"
    xml.dc :identifier, "id_#{SecureRandom.hex}", "id" => "pub-id"
    xml.meta Time.now.utc.iso8601, "property" => "dcterms:modified"
  end
  xml.manifest do
    unless cover.nil?
      xml.item "id" => "cover-image", "href" => "cover.png",     "media-type" => "image/png",             "properties" => "cover-image"
    end
    xml.item "id" => "htmltoc",     "href" => "toc.xhtml",     "media-type" => "application/xhtml+xml", "properties" => "nav"
    xml.item "id" => "article",     "href" => "article.xhtml", "media-type" => "application/xhtml+xml"
    xml.item "id" => "css",         "href" => "css.css",       "media-type" => "text/css"
    images.each do |image|
      xml.item "id" => "id_#{image.filename.parameterize(separator: '_')}", "href" => "images/#{image.filename}", "media-type" => image.content_type
    end
  end
  xml.spine do
    xml.itemref "idref" => "article"
    xml.itemref "idref" => "htmltoc"
  end
end
