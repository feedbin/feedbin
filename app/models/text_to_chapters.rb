class TextToChapters
  TIMESTAMP_PATTERN = /((?:\d+:)?\d{1,2}:\d{2})/
  CHAPTER_LINE      = /^#{TIMESTAMP_PATTERN}\s+(.+)$/
  CHAPTER_BLOCK     = /(?:^#{TIMESTAMP_PATTERN}\s+.+$\n?){2,}/m

  def self.call(text)
    chapter_block = text[CHAPTER_BLOCK]
    return [] unless chapter_block

    chapter_block.scan(CHAPTER_LINE).map do |timestamp, title|
      seconds = timestamp.split(":").map(&:to_i).reverse.each_with_index.sum do |number, index|
        number * (60 ** index)
      end
      {
        seconds: seconds,
        timestamp: timestamp,
        title: title.strip
      }
    end
  end
end
