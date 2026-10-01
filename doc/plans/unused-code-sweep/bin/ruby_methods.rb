# Steps 4 and 5: Ruby methods with no caller, found with Prism (Ruby's parser).
# Usage: ruby $SWEEP/bin/ruby_methods.rb <category> <dir> [<dir> ...]
#   ruby $SWEEP/bin/ruby_methods.rb helpers app/helpers app/presenters
#
# A method is "referenced" when its name appears anywhere as a call, a symbol,
# or a word in a string, in any Ruby file, or as a word in any template or
# script. This is name-based: two methods with one name hide each other, which
# errs on the side of "used".
require_relative "lib"
require "prism"

category, *dirs = ARGV
abort "usage: ruby_methods.rb <category> <dir>..." if dirs.empty?

# Names that frameworks call by themselves (spec 5.1 item 4).
ENTRY = %w[
  initialize perform call view_template before_template after_template around_template
  to_param to_s to_h to_a to_json as_json to_partial_path inspect hash eql? == <=> ===
  each method_missing respond_to_missing? included extended inherited prepended
  default_url_options url_options cache_key cache_key_with_version cache_version
  serializable_hash read_attribute_for_serialization coerce
  append_info_to_payload verified_request? cast serialize deserialize changed_in_place?
  marshal_load marshal_dump store_dir filename extension_allowlist default_url
  fog_attributes fog_public fog_authenticated_url_expiration
].to_set

class Collector < Prism::Visitor
  attr_reader :defs, :names

  def initialize(file)
    @file = file
    @defs = []
    @names = Hash.new(0)
    super()
  end

  def visit_def_node(node)
    @defs << [node.name.to_s, @file, node.location.start_line]
    super
  end

  def visit_call_node(node)
    add(node.name.to_s)
    super
  end

  def visit_symbol_node(node)
    add(node.unescaped.to_s)
    super
  end

  def visit_string_node(node)
    node.unescaped.to_s.dup.force_encoding(Encoding::UTF_8).scrub.scan(/[A-Za-z_][A-Za-z0-9_]*[?!]?/) { |w| add(w) }
    super
  end

  private

  def add(name)
    @names[name] += 1
    @names[name.delete_suffix("=")] += 1 if name.end_with?("=")
  end
end

def ruby_file?(f) = f.end_with?(".rb", ".rake") || f.start_with?("bin/") || f == "Gemfile"

def scan(files)
  names = Hash.new(0)
  defs = []
  files.each do |f|
    next unless File.file?(f)
    src = File.read(f).scrub
    if ruby_file?(f)
      result = Prism.parse(src, filepath: f)
      c = Collector.new(f)
      result.value.accept(c)
      defs.concat(c.defs)
      c.names.each { |k, v| names[k] += v }
    else
      src.scan(/[A-Za-z_][A-Za-z0-9_]*[?!]?/) { |w| names[w] += 1 }
    end
  end
  [defs, names]
end

ls = ->(paths) { Open3.capture2("git", "ls-files", "--", *paths, *EXCLUDES).first.lines.map(&:chomp) }
target_files = ls.call(dirs).select { |f| ruby_file?(f) }
prod_files = ls.call(PROD_PATHS)
test_files = ls.call(TEST_PATHS)

defs, _ = scan(target_files)
_, prod_names = scan(prod_files)
_, test_names = scan(test_files)

rows = defs.map do |name, file, line|
  bare = name.sub(/[?!=]\z/, "")
  prod = prod_names[name] + ((bare == name) ? 0 : prod_names[bare])
  test = test_names[name] + ((bare == name) ? 0 : test_names[bare])
  if ENTRY.include?(name) || name.start_with?("visit_")
    Row.new("kept", name, "#{file}:#{line}", [], [], "framework entry point")
  else
    classify(name, "#{file}:#{line}", Array.new(prod, "ref"), Array.new(test, "ref"))
  end
end

write_rows(category, rows)
