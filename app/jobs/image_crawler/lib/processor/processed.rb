module ImageCrawler
  module Processor
    class Processed
      attr_reader :file

      def self.from_pipeline(pipeline)
        path = File.join(Dir.tmpdir, ["image_processed_", SecureRandom.hex, ".#{pipeline.options[:format]}"].join)
        pipeline.call(destination: path)
        new(path)
      end

      # The mean colour as six hex digits.
      def self.average_color(image)
        average(image).first(3).map { "%02x" % it }.join
      end

      # The mean of each band: the image shrunk to one pixel.
      def self.average(image)
        ImageProcessing::Vips
          .source(image)
          .resize_to_fill(1, 1, sharpen: false)
          .call(save: false)
          .getpoint(0, 0)
      end

      def initialize(file)
        @file = file
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
        self.class.average_color(source)
      end
    end
  end
end
