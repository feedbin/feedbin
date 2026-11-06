namespace :api_docs do
  desc "Regenerate feedbin-api-docs' examples from the v3 API (API_DOCS= the docs checkout, default ../feedbin-api-docs)"
  task :examples do
    system({"API_DOCS_WRITE" => "1"}, "bin/rails", "test", "test/api_docs/examples_test.rb", exception: true)
  end
end
