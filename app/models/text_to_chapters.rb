class TextToChapters
  TIMESTAMP_PATTERN = /((?:\d+:)?\d{1,2}:\d{2})/
  CHAPTER_LINE      = /^#{TIMESTAMP_PATTERN}\s+(.+)$/
  CHAPTER_BLOCK     = /(?:^#{TIMESTAMP_PATTERN}\s+.+$\n?){2,}/m

  def self.call(text, total_duration)
    chapter_block = text[CHAPTER_BLOCK]
    return [] unless chapter_block

    chapters = chapter_block.scan(CHAPTER_LINE).map do |timestamp, title|
      seconds = timestamp.split(":").map(&:to_i).reverse.each_with_index.sum do |number, index|
        number * (60 ** index)
      end
      {
        seconds: seconds,
        timestamp: timestamp,
        title: title.strip
      }
    end

    chapters.each_with_index do |chapter, index|
      if index < chapters.length - 1
        chapter[:duration] = chapters[index + 1][:seconds] - chapter[:seconds]
      else
        chapter[:duration] = total_duration ? total_duration - chapter[:seconds] : nil
      end
    end

    chapters
  end
end
