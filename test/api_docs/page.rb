module ApiDocs
  # One page of feedbin-api-docs: an endpoint (_endpoints/<resource>/<name>.md)
  # or an object (_objects/<name>.md). An endpoint's front matter is the
  # request: method, route or example_path, example_query and request, the
  # same fields the docs' curl example is built from, so the two can't
  # disagree. {feed_id}, {entry_id} and {subscription_id} fill from a source
  # in _data/sources.yml.
  class Page
    TOKEN = /\{(\w+_id)\}/

    attr_reader :key, :front_matter

    def self.endpoints(root)
      Dir[File.join(root, "_endpoints/*/*.md")].sort.map { new(root, it) }
    end

    def initialize(root, path)
      @key = path.delete_prefix(File.join(root, "_endpoints/")).delete_suffix(".md")
      @front_matter = YAML.safe_load(File.read(path)[/\A---\n(.*?)\n---/m, 1], permitted_classes: [Date])
    end

    def method
      front_matter.fetch("method").downcase.to_sym
    end

    def authenticated?
      front_matter["authenticated"] != false
    end

    def path(source)
      "/v3#{fill(front_matter["example_path"] || front_matter.fetch("route"), source)}"
    end

    # The query as [[name, value]] pairs, decoded: the docs write it the way
    # a reader would type it, such as with spaces in a search.
    def query(source)
      text = front_matter["example_query"] or return []
      fill(text, source).split("&").map { |pair| pair.split("=", 2).map { CGI.unescape(it.to_s) } }
    end

    def body(source)
      front_matter["request"]&.then { fill(it.strip, source) }
    end

    # The tokens the request uses, such as "entry_id".
    def tokens
      [front_matter["example_path"], front_matter["example_query"], front_matter["request"]].compact.flat_map { it.scan(TOKEN).flatten }.uniq
    end

    private

    def fill(text, source)
      text.gsub(TOKEN) { source.fetch($1) }
    end
  end
end
