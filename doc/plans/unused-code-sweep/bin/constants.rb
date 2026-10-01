# Step 5: classes and modules with no reference, and jobs with no enqueue.
# Usage: ruby $SWEEP/bin/constants.rb
# Jobs (classes under app/jobs that define perform) go to the decision list (spec 5.2 item 1).
require_relative "lib"
require "prism"

# Not here: app/controllers (routes reach them, step 1), app/helpers (Rails
# includes every helper module), config/initializers/core_ext (reopens library
# constants; its methods are covered by ruby_methods.rb).
DIRS = %w[app/models app/jobs app/presenters app/mailers app/uploaders lib config/initializers :(exclude)config/initializers/core_ext].freeze

class Defs < Prism::Visitor
  attr_reader :found

  def initialize(file)
    @file = file
    @stack = []
    @found = []
    super()
  end

  def visit_class_node(node) = record(node) { super }
  def visit_module_node(node) = record(node) { super }

  private

  def record(node)
    name = node.constant_path.slice
    @stack.push(name)
    body = node.body&.slice.to_s
    @found << [@stack.join("::"), name.split("::").last, node.location.start_line, body.match?(/\bdef perform\b/)]
    yield
    @stack.pop
  end
end

files = Open3.capture2("git", "ls-files", "--", *DIRS).first.lines.map(&:chomp).select { |f| f.end_with?(".rb") }
rows = []
files.each do |file|
  v = Defs.new(file)
  Prism.parse_file(file).value.accept(v)
  v.found.each do |full, short, line, perform|
    prod, test = refs(short, own_files: [file], boundary: "A-Za-z0-9_")
    job = file.start_with?("app/jobs/") && perform
    rows << if short == "ClassMethods"
      Row.new("kept", full, "#{file}:#{line}", [], test, "ActiveSupport::Concern ClassMethods")
    elsif short.end_with?("Presenter") && File.exist?("app/models/#{short.delete_suffix("Presenter").gsub(/([a-z\d])([A-Z])/, '\\1_\\2').downcase}.rb")
      Row.new("kept", full, "#{file}:#{line}", [], test, "ApplicationHelper#present builds \"\#{object.class}Presenter\"")
    else
      classify(full, "#{file}:#{line}", prod, test, decision: job, note: job ? "job: no enqueue in this repo" : nil)
    end
  end
end
write_rows("constants", rows.uniq { |r| [r.unit, r.defined_at] })
