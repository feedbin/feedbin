module ImageCrawler
  module Processor
    class Processed

      attr_reader :file, :extension

      def self.from_pipeline(pipeline)
        extension = pipeline.options[:format]
        path = persisted_path(extension)
        pipeline.call(destination: path)
        new(path, extension)
      end

      def self.from_file(file, extension)
        destination = persisted_path(extension)
        FileUtils.cp file, destination
        new(destination, extension)
      end

      def self.persisted_path(extension)
        File.join(Dir.tmpdir, ["image_processed_", SecureRandom.hex, ".#{extension}"].join)
      end

      def initialize(file, extension)
        @file = file
        @extension = extension
      end

      def source
        @source ||= Vips::Image.new_from_file(@file)
      end

      def size
        File.size(@file)
      end

      def width
        source.width
      end

      def height
        source.height
      end

      def fingerprint
        Digest::MD5.file(@file).hexdigest
      end

      def placeholder_color
        hex = nil
        file = ImageProcessing::Vips
          .source(source)
          .resize_to_fill(1, 1, sharpen: false)
          .custom { |image|
            image.tap do |data|
              hex = data.getpoint(0, 0).map { |value| "%02x" % value }.first(3).join
            end
          }.call
        file.unlink
        hex
      end
    end
  end
end