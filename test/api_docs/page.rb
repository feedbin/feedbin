module ApiDocs
  # A docs page. An endpoint's request is read from the same front matter its
  # curl example uses; {feed_id}-style tokens fill from _data/sources.yml.
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

    # Decoded: the docs write queries as typed, e.g. with spaces.
    def query(source)
      text = front_matter["example_query"] or return []
      fill(text, source).split("&").map { |pair| pair.split("=", 2).map { CGI.unescape(it.to_s) } }
    end

    def body(source)
      front_matter["request"]&.then { fill(it.strip, source) }
    end

    def tokens
      [front_matter["example_path"], front_matter["example_query"], front_matter["request"]].compact.flat_map { it.scan(TOKEN).flatten }.uniq
    end

    private

    def fill(text, source)
      text.gsub(TOKEN) { source.fetch($1) }
    end
  end
end
