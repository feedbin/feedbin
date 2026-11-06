require_relative "page"
require_relative "world"

# Generates feedbin-api-docs' examples by running each page's request against
# ApiDocs::World. Written by `bin/rails api_docs:examples`.
module ApiDocs
  # The docs' "now".
  NOW = Time.utc(2026, 9, 9, 17, 4, 11)
  TOKEN = "fbn_v3_4f9c2a7e1b8d4c6f9a0e3b5d7c1f2a8e"
  REQUEST_ID = "5f0c9d0e-7a7b-4f43-9a52-0c1f0f8f2d61"
  HOST = "api.feedbin.com"

  # Production hosts, and fixed secrets so signed values are stable.
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

  # per_source: run once per source, yielding it. request: overrides the front matter's request.
  Scenario = Data.define(:per_source, :setup, :request)

  # An object (_data/objects/<name>.json, the JSON Pointer `pick` into the
  # response) or a snippet (_data/snippets/<name>.json, the whole response).
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
