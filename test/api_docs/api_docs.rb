require_relative "page"
require_relative "world"

# Generates feedbin-api-docs' examples from the real v3 API. Each endpoint
# page's request runs against ApiDocs::World, the docs' fake account, and the
# response is written to the docs repo as _data/responses/<page>.json.
# Object pages' examples come from the requests in scenarios.rb. See
# examples_test.rb, and `bin/rails api_docs:examples`.
module ApiDocs
  # The docs' "now": every example's as_of, and the clock requests run at.
  NOW = Time.utc(2026, 9, 9, 17, 4, 11)
  TOKEN = "fbn_v3_4f9c2a7e1b8d4c6f9a0e3b5d7c1f2a8e"
  REQUEST_ID = "5f0c9d0e-7a7b-4f43-9a52-0c1f0f8f2d61"
  HOST = "api.feedbin.com"

  # Production's public hosts, so URLs in examples look like the real ones,
  # and fixed secrets, so anything signed with them is the same every run.
  ENVIRONMENT = {
    "UNIFIED_IMAGE_HOST" => "https://images.feedbin.com",
    "EXTRACT_HOST" => "https://extract.feedbin.com",
    "EXTRACT_USER" => "feedbin",
    "EXTRACT_SECRET" => "docs-extract-secret",
    "NEWSLETTER_HOST" => "newsletters.feedbin.com",
    "NEWSLETTER_ADDRESS_HOST" => "feedb.in",
    "PAGES_DOMAIN" => "pages.feedbin.com",
    "CAMO_HOST" => nil,
    "CAMO_KEY" => nil
  }.freeze

  # What a page needs beyond the shared world. per_source: run the page once
  # for each source, as the docs' example switcher shows it; the block gets
  # the source. request: replaces what the front matter can't express, such
  # as a non-JSON body.
  Scenario = Data.define(:per_source, :setup, :request)

  # An example that isn't an endpoint page's own response: a request (a
  # path, with tokens, and a JSON body for a POST). An object page's example
  # (_objects/<name>.md) is _data/objects/<name>.json, the object at pick, a
  # JSON Pointer into the response. A snippet, for a page's prose, is
  # _data/snippets/<name>.json, the whole response.
  Example = Data.define(:kind, :name, :method, :path, :body, :per_source, :pick, :setup)

  @scenarios = {}
  @examples = []

  class << self
    attr_reader :scenarios, :examples

    def scenario(key, per_source: false, request: nil, &setup)
      @scenarios[key] = Scenario.new(per_source: per_source, setup: setup, request: request)
    end

    def object(name, path, method: :get, body: nil, per_source: false, pick: nil, &setup)
      @examples << Example.new(kind: "objects", name: name, method: method, path: path, body: body, per_source: per_source, pick: pick, setup: setup)
    end

    def snippet(name, path, method: :get, body: nil, &setup)
      @examples << Example.new(kind: "snippets", name: name, method: method, path: path, body: body, per_source: false, pick: nil, setup: setup)
    end

    def docs_root
      ENV.fetch("API_DOCS") { Rails.root.join("../feedbin-api-docs").to_s }
    end

    def sources
      YAML.load_file(File.join(docs_root, "_data/sources.yml"))
    end

    def write?
      ENV["API_DOCS_WRITE"].present?
    end
  end
end

require_relative "scenarios"
