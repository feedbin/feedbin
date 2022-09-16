# frozen_string_literal: true

module Crawler
  module Image
    class FindImageCritical
      include Sidekiq::Worker
      sidekiq_options queue: "image_parallel_critical", retry: false
      def perform(*args)
        FindImage.new.perform(*args)
      end
    end
  end
end