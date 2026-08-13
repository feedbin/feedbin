module FaviconCrawler
  class Image
    def self.resize(*args)
      new(*args).resize
    end

    def resize
      return unless ImageFormat.allowed?(@path)

      image = ImageCrawler::Processor::IconLayer.best(@path)

      return unless image.present?

      ImageProcessing::Vips
        .source(image)
        .resize_to_fit(32, 32)
        .saver(strip: true)
        .convert("png")
        .call
    end

    private

    def initialize(path)
      @path = path
    end
  end
end
