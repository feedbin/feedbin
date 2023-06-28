autoloader = Rails.autoloaders.main
autoloader.collapse("app/jobs/feed_crawler/lib")
autoloader.collapse("app/jobs/image_crawler/lib")
