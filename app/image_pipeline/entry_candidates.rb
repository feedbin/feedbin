class EntryCandidates < Candidates

  def find_image
    image = nil
    candidates = document_candidates
    candidates.push(ImageCandidate.new(@entry.url, "iframe"))
    if download = try_candidates(candidates)
      image = download
    end
    image
  end

  def document_candidates
    Nokogiri::HTML5(@entry.content).search("img, iframe").each_with_object([]) do |element, array|
      next if element["src"].blank?
      src = element["src"].strip
      next if src.start_with? "data"
      if src.start_with?('//')
        src = "http:#{src}"
      end
      if !src.start_with?('http')
        if src.start_with? '/'
          base = @feed.site_url
        else
          base = @entry.url || ""
        end
        begin
          src = URI.join(base, src).to_s
        rescue
          next
        end
      end
      array.push(ImageCandidate.new(src, element.name))
    end
  end

end