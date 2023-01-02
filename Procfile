feedbin_clock: bundle exec clockwork lib/clock.rb
feedbin_jobs: SKIP_IMAGES=true DB_POOL=10 bundle exec sidekiq --config config/sidekiq-development.yml
feedbin_css: bin/rails tailwindcss:watch