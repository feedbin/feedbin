# Finds methods that nothing calls. Static index (method_index.rb) plus runtime
# checks against the loaded app. Needs the test database (run outside the sandbox):
#
#   RAILS_ENV=test bin/rails runner doc/plans/unused-code-sweep/bin/dead_methods.rb
#
# Writes tmp/dead_methods/candidates.tsv, kept.tsv and open_sends.tsv, and
# prints bucket counts. Reads tmp/dead_methods/coverage/*.json when
# coverage_hook.rb produced them.
#
# A reference "reaches" a def when it could call it:
#   symbols, words in strings/templates, top-level and instance_exec code: always
#   obj.name (unknown receiver): always, unless the def is private
#   Const.name: when Const's singleton class holds the def (or Const is a
#     mailer and the def is a public instance method)
#   name / self.name / super: when the caller's class and the def's class can
#     be the same object (one includes or inherits the other, directly or
#     through a class that includes a module)
# Anything that cannot be resolved counts as reaching.
#
# Buckets, strongest evidence first:
#   1-shadowed           a later def in the same module replaces this one
#   2-no-reference       nothing anywhere names it
#   3-test-only          only tests reach it
#   4-only-from-dead     only other dead methods reach it
#   5-name-used-elsewhere  the name is used, but no use can reach this owner
#   6-loose-pattern      unreached, but an interpolated string could build the name
#   7-unresolved         the owner is not loaded and nothing names the method
#   8-gem-word           unreached, but the name is a word in gem/stdlib source
#                        (could be a hook that a library calls)
require_relative "method_index"
require "json"
require "fileutils"

ROOT = Rails.root.to_s
OUT = File.join(ROOT, "tmp/dead_methods")
FileUtils.mkdir_p(OUT)

ENTRY = %w[
  initialize initialize_copy initialize_dup initialize_clone method_missing respond_to_missing?
  inherited included extended prepended method_added const_missing
].to_set

STARTED = Process.clock_gettime(Process::CLOCK_MONOTONIC)
LOG = File.open(File.join(OUT, "run.log"), "w").tap { it.sync = true }
def log(msg)
  line = format("[dead_methods %6.1fs] %s", Process.clock_gettime(Process::CLOCK_MONOTONIC) - STARTED, msg)
  LOG.puts(line)
  warn(line)
end

# ---------------------------------------------------------------- load the app

Rails.application.deprecators.silenced = true
Rails.application.eager_load!
ActiveRecord::Base.descendants.each do |model|
  model.define_attribute_methods unless model.abstract_class?
rescue ActiveRecord::StatementInvalid
  # Engine tables (ActionText, ActiveStorage) that this app never created.
end

# --------------------------------------------------------------- static index

files = `git ls-files -- app lib config db test bin script Rakefile config.ru Procfile`.lines.map(&:chomp)
files.reject! { it.start_with?("app/assets/", "app/javascript/", "vendor/") }
files.select! { File.file?(it) }

index = MethodIndex.new
parse_errors = []
files.each do |path|
  test = path.start_with?("test/")
  source = File.read(path).scrub
  if path.end_with?(".rb", ".rake", ".builder", ".jbuilder", "Rakefile", "config.ru") || (path.start_with?("bin/") && source.start_with?("#!/usr/bin/env ruby"))
    result = index.add_ruby(source, path: path, test: test)
    parse_errors << path unless result.errors.empty?
  elsif path.end_with?(".erb")
    ruby = ActionView::Template::Handlers::ERB::Erubi.new(source, trim: true).src
    result = index.add_ruby(ruby, path: path, test: test)
    unless result.errors.empty?
      parse_errors << path
      index.add_text(source, path: path, test: test)
    end
  elsif path.end_with?(".yml", ".yaml", ".json", ".txt") || path.include?("Procfile")
    index.add_text(source, path: path, test: test)
  end
end
log "indexed #{files.size} files, #{index.defs.size} defs, #{index.refs.size} refs, #{index.patterns.size} patterns, #{index.open_sends.size} open sends"
log "erb files read as plain text (did not parse as Ruby): #{parse_errors.size}" if parse_errors.any?

refs_by_name = index.refs.group_by(&:name)

# --------------------------------------------------------- constant lookup

# Strict: each segment must be defined directly in the one before it.
RESOLVED = {}
def resolve(name)
  return nil if name.nil? || name.empty? || name.include?("?")
  return RESOLVED[name] if RESOLVED.key?(name)
  RESOLVED[name] = begin
    name.delete_prefix("::").split("::").reduce(Object) { |mod, seg| mod.const_get(seg, false) }
  rescue NameError, ArgumentError, TypeError
    nil
  end
end

def resolve_first(candidates) = Array(candidates).lazy.map { resolve(it) }.find { it.is_a?(Module) }

# Ruby's order for a constant written in code: lexical scopes, then the
# ancestors of the innermost scope, then the top level.
def resolve_const(path, nesting)
  return resolve(path) if path.start_with?("::")
  first, rest = path.split("::", 2)
  base = Array(nesting).lazy.map { resolve(it) }.find { it&.const_defined?(first, false) }&.const_get(first, false)
  base ||= begin
    resolve(Array(nesting).first)&.const_get(first)
  rescue
    nil
  end
  base ||= resolve(first)
  return base unless rest
  base.is_a?(Module) ? begin
    rest.split("::").reduce(base) { |m, seg| m.const_get(seg) }
  rescue
    nil
  end : nil
end

# ------------------------------------------------------------ relatedness

ALL_CLASSES = ObjectSpace.each_object(Class).reject(&:singleton_class?)
# Modules that can extend an app module: every class, plus modules defined in this app.
APP_MODULES = index.defs.filter_map { resolve_first(it.owner_candidates) }.uniq.reject { it.is_a?(Class) }
EXTEND_SCOPE = ALL_CLASSES + APP_MODULES

def le?(a, b)
  (a <= b) || false
rescue TypeError, ArgumentError
  false
end

# Classes whose instances have mod in their ancestors.
def includers(mod) = (@includers ||= {})[mod] ||= ALL_CLASSES.select { it.include?(mod) }

# Modules that extend mod (their singleton class has mod as an ancestor).
def extenders(mod) = (@extenders ||= {})[mod] ||= EXTEND_SCOPE.select { it.singleton_class.include?(mod) }

def descendants(klass) = (@descendants ||= {})[klass] ||= klass.descendants

def instance_kinds(ctx) = ctx.is_a?(Class) ? [ctx, *descendants(ctx)] : [ctx, *includers(ctx)]
def singleton_kinds(ctx) = ctx.is_a?(Class) ? [ctx, *descendants(ctx)] : [ctx, *includers(ctx), *extenders(ctx)].uniq

# Can a receiverless call written in ctx (instance side) reach a method held by holder?
RELATED = {}
def related_instance?(ctx, holder)
  RELATED.fetch([:i, ctx, holder]) do
    RELATED[[:i, ctx, holder]] = le?(ctx, holder) || le?(holder, ctx) || instance_kinds(ctx).any? { le?(it, holder) }
  end
end

def related_singleton?(ctx, holder)
  RELATED.fetch([:s, ctx, holder]) do
    RELATED[[:s, ctx, holder]] = singleton_kinds(ctx).any? { le?(it.singleton_class, holder) }
  end
end

# ------------------------------------------------------------ runtime facts

# Where the def lives at runtime.
#   inst: the module whose instances get it (nil for singleton-only defs)
#   sing: the module that holds it for class-level calls (nil for instance-only)
Place = Struct.new(:status, :inst, :sing, :vis)

def place(d)
  owner = resolve_first(d.owner_candidates)
  return Place.new(status: :unresolved) unless owner

  primary =
    if d.via == :class_methods then begin
      owner.const_get(:ClassMethods, false)
    rescue
      nil
    end
    elsif d.side == :singleton then owner.singleton_class
    else owner
    end
  um = primary && begin
    primary.instance_method(d.name)
  rescue
    nil
  end
  return Place.new(status: :unresolved) unless um

  status =
    if um.source_location == [File.join(ROOT, d.path), d.line] then :ok
    elsif um.owner == primary then :shadowed
    else :prepended # a module in front calls this def through super
    end
  vis = if primary.private_method_defined?(d.name) then :private
  elsif primary.protected_method_defined?(d.name) then :protected
  else :public
  end
  inst = (d.side == :singleton) ? nil : owner
  sing = case d.side
  when :singleton then primary
  when :both then owner.singleton_class
  else owner unless owner.is_a?(Class) # a module's instance methods reach class level through extend
  end
  Place.new(status: status, inst: inst, sing: sing, vis: vis)
end

def defines?(mod, name)
  mod.method_defined?(name.to_sym, false) || mod.private_method_defined?(name.to_sym, false)
end

# True when something after the holder in a lookup chain defines the name too:
# the framework or a parent class can call this def as an override.
def overrides?(holder, name)
  chains =
    if holder.is_a?(Class) then [holder.ancestors]
    else [holder.ancestors, *includers(holder).map(&:ancestors), *extenders(holder).map { it.singleton_class.ancestors }]
    end
  chains.any? do |chain|
    i = chain.index(holder)
    i && chain[(i + 1)..].any? { defines?(it, name) }
  end
end

ROUTED = Rails.application.routes.routes.filter_map do |r|
  r.defaults[:controller] && r.defaults[:action] && "#{r.defaults[:controller]}##{r.defaults[:action]}"
end.to_set

def routed?(holder, name)
  return false unless holder.is_a?(Class) && holder < AbstractController::Base
  [holder, *holder.descendants].any? do |k|
    k.respond_to?(:controller_path) && !k.abstract? && ROUTED.include?("#{k.controller_path}##{name}")
  end
end

def mailer?(mod) = mod.is_a?(Class) && le?(mod, ActionMailer::Base)

# Words in bundled gem sources and the Ruby standard library.
def gem_words
  key = Digest::SHA256.hexdigest([File.read(File.join(ROOT, "Gemfile.lock")), RUBY_VERSION].join)
  cache = File.join(OUT, "gem_words-#{key[0, 12]}.marshal")
  return Marshal.load(File.binread(cache)) if File.exist?(cache)

  dirs = Bundler.load.specs.map(&:full_gem_path).uniq
  words = Set.new
  files = dirs.flat_map { Dir.glob(File.join(it, "{lib,app}/**/*.{rb,erb}")) }
  files += Dir.glob(File.join(RbConfig::CONFIG["rubylibdir"], "**/*.rb"))
  files.each do |file|
    File.read(file).scrub.scan(MethodIndex::WORD) { words << it }
  rescue Errno::ENOENT, Errno::EISDIR
  end
  File.binwrite(cache, Marshal.dump(words))
  words
end

PATTERNS = index.patterns
def dynamic_pattern(name, strength)
  PATTERNS.find do |type, frag, _, _, str|
    str == strength && name != frag && ((type == :prefix) ? name.start_with?(frag) : name.end_with?(frag))
  end
end

def coverage
  @coverage ||= Dir.glob(File.join(OUT, "coverage/*.json")).each_with_object(Hash.new(0)) do |file, acc|
    JSON.parse(File.read(file)).each do |path, methods|
      methods.each { |name, line, count| acc[[path, line, name]] += count }
    end
  end
end

# ---------------------------------------------------------- reach analysis

def ref_names(name) = name.end_with?("=") ? [name, name.delete_suffix("=")] : [name]

def const_reaches?(const, place)
  return true unless const.is_a?(Module)
  (place.sing && le?(const.singleton_class, place.sing)) ||
    (place.inst && mailer?(const) && place.vis == :public && le?(const, place.inst))
end

def context_reaches?(ctx, side, place)
  return true unless ctx
  (place.inst && %i[instance both].include?(side) && related_instance?(ctx, place.inst)) ||
    (place.sing && %i[singleton both].include?(side) && related_singleton?(ctx, place.sing))
end

def reaches?(ref, d, place)
  if d.name.end_with?("=") && ref.name != d.name
    return %i[symbol word].include?(ref.kind) # "foo" reaches foo= only as a hash key or a word
  end
  return true if %i[symbol word].include?(ref.kind) || ref.side == :global

  case ref.receiver
  when :other then place.vis != :private
  when :const then const_reaches?(resolve_const(ref.const, ref.nesting), place)
  else context_reaches?(resolve_first(ref.owner_candidates), ref.side, place)
  end
end

REVIEWED_SENDS = File.readlines(File.join(__dir__, "open_sends_reviewed.tsv"), chomp: true)
  .reject { it.start_with?("#") || it.strip.empty? }
  .map { it.split("\t") }

# The reviewed names regexp for a send site, :none when it adds no names, or nil if unreviewed.
def reviewed(send)
  line = File.readlines(send.path)[send.line - 1].to_s
  row = REVIEWED_SENDS.find { |path, snippet, _| path == send.path && line.include?(snippet) }
  return nil unless row
  (row[2] == "-") ? :none : Regexp.new(row[2])
end

ReviewedSend = Struct.new(*MethodIndex::OpenSend.members, :names)
PROD_OPEN_SENDS = index.open_sends.reject(&:test).filter_map do |s|
  names = reviewed(s)
  ReviewedSend.new(**s.to_h, names: names) unless names == :none
end
# Resolved once: [send, receiver constant or context module].
SCOPED_SENDS = PROD_OPEN_SENDS.filter_map do |s|
  case s.receiver
  when :const then [s, resolve_const(s.const, s.nesting)] if s.const
  when :none, :self then [s, resolve_first(s.owner_candidates)] unless s.side == :global
  end
end

# send/public_send/try with a non-literal name, on a receiver that can hold this def.
def open_send_for(name, place)
  SCOPED_SENDS.find do |s, mod|
    next false if s.names && !s.names.match?(name)
    (s.receiver == :const) ? const_reaches?(mod, place) : context_reaches?(mod, s.side, place)
  end&.first
end

# ------------------------------------------------------------------ classify

words = gem_words
log "gem and stdlib words: #{words.size}"

Row = Struct.new(:def, :status, :place, :reason, :prod, :test, :name_prod, :loose, :gem)
rows = []
kept = []

index.defs.each_with_index do |d, i|
  log "checked #{i} of #{index.defs.size} defs" if (i % 250).zero?
  next if d.test || d.path.start_with?("db/migrate/", "bin/", "script/")
  label = "#{d.owner}#{(d.side == :singleton) ? "." : "#"}#{d.name}"
  keep = ->(reason) { kept << [reason, label, "#{d.path}:#{d.line}"] }
  next keep.call("dynamic def") if d.dynamic
  next keep.call("def inside a template") if d.path.end_with?(".erb", ".jbuilder", ".builder")
  next keep.call("operator") unless d.name.match?(/\A[A-Za-z_]/)
  next keep.call("entry point") if ENTRY.include?(d.name)
  if (pat = dynamic_pattern(d.name, :call))
    next keep.call("dynamic call pattern #{pat[0]} #{pat[1]} at #{pat[2]}:#{pat[3]}")
  end
  gem = words.include?(d.name) || words.include?(d.name.delete_suffix("="))
  loose = dynamic_pattern(d.name, :loose)
  named = ref_names(d.name).flat_map { refs_by_name[it] || [] }
    .reject { it.kind == :const || (it.path == d.path && it.line.between?(d.line, d.end_line)) }

  place = place(d)
  case place.status
  when :shadowed
    rows << Row.new(def: d, status: :shadowed, place: place, prod: [], test: [], name_prod: 0)
    next
  when :unresolved
    next keep.call("unresolved owner, name is a gem word") if gem
    next keep.call("unresolved owner, name referenced") if named.any? { !it.test }
    rows << Row.new(def: d, status: :unresolved, place: place, prod: [], test: named.select(&:test), name_prod: 0)
    next
  when :prepended
    next keep.call("prepended module calls it through super")
  end

  primary = place.sing || place.inst
  next keep.call("overrides an ancestor") if overrides?(primary, d.name)
  next keep.call("routed action") if place.vis == :public && place.inst && routed?(place.inst, d.name)
  if (s = open_send_for(d.name, place))
    next keep.call("open send at #{s.path}:#{s.line}")
  end

  reaching = named.select { reaches?(it, d, place) }
  rows << Row.new(def: d, status: :checked, place: place, prod: reaching.reject(&:test), test: reaching.select(&:test),
    name_prod: named.count { !it.test }, loose: loose, gem: gem)
end

# Second order: references that sit inside dead defs do not count.
strong = ->(r) { r.status == :shadowed || (r.status == :checked && !r.loose && !r.gem && r.prod.empty?) }
dead = rows.select(&strong).map(&:def).to_set
loop do
  ranges = dead.group_by(&:path)
  inside_dead = ->(ref) { (ranges[ref.path] || []).any? { |dd| ref.line.between?(dd.line, dd.end_line) } }
  newly = rows.select { it.status == :checked && it.reason != :second_order && it.prod.any? && it.prod.all?(&inside_dead) }
  break if newly.empty?
  newly.each { it.reason = :second_order }
  dead.merge(newly.reject { it.loose || it.gem }.map(&:def))
end

def bucket(row)
  return "1-shadowed" if row.status == :shadowed
  return "7-unresolved" if row.status == :unresolved
  return nil unless row.prod.empty? || row.reason == :second_order
  return "8-gem-word" if row.gem
  return "6-loose-pattern" if row.loose
  return "4-only-from-dead" if row.reason == :second_order
  return "3-test-only" if row.test.any?
  row.name_prod.zero? ? "2-no-reference" : "5-name-used-elsewhere"
end

def label(d) = "#{d.owner}#{(d.side == :singleton) ? "." : "#"}#{d.name}"

File.open(File.join(OUT, "candidates.tsv"), "w") do |f|
  f.puts %w[bucket method visibility location prod_refs test_refs name_refs coverage note].join("\t")
  rows.filter_map { |r| (b = bucket(r)) && [b, r] }.sort_by { |b, r| [b, r.def.path, r.def.line] }.each do |b, r|
    d = r.def
    cov = coverage.empty? ? "-" : coverage[[d.path, d.line, d.name]].to_s
    note = (r.prod.first(3) + r.test.first(3)).map { "#{it.path}:#{it.line}" }.join(" ")
    note = "pattern #{r.loose[1]} at #{r.loose[2]}:#{r.loose[3]}; #{note}" if r.loose
    f.puts [b, label(d), r.place&.vis, "#{d.path}:#{d.line}", r.prod.size, r.test.size, r.name_prod, cov, note].join("\t")
  end
end

File.open(File.join(OUT, "kept.tsv"), "w") do |f|
  f.puts %w[reason method location].join("\t")
  kept.sort.each { f.puts it.join("\t") }
end

# Unknown-receiver open sends cannot be scoped. Check them by hand for each candidate.
File.open(File.join(OUT, "open_sends.tsv"), "w") do |f|
  PROD_OPEN_SENDS.select { it.receiver == :other }.each { f.puts "#{it.path}:#{it.line}" }
end

# ---------------------------------------------------------------- namespaces
# A class or module is unreferenced when nothing outside its own bodies names
# it: no constant reference or call (Phlex kit style) with its last segment, and
# no word or symbol equal to its full name, its underscored name, or the plural
# of that (associations, YAML, strings). A namespace with a referenced child
# namespace counts as referenced.
#
# Kept by convention: routed controllers, helpers (Rails includes them all),
# *Presenter (app/helpers/application_helper.rb builds the name at runtime).
DYNAMIC_CONST_SUFFIXES = %w[Presenter].freeze

namespaces = index.namespaces.reject { it.test || it.path.start_with?("db/migrate/", "bin/", "script/") }
bodies = namespaces.group_by(&:name)
words_and_consts = index.refs.select { %i[const call word symbol].include?(it.kind) }.group_by(&:name)

ns_refs = bodies.to_h do |name, defs|
  mod = resolve(name)
  last = name.split("::").last
  under = last.underscore
  keys = [last, name, under, under.pluralize, name.underscore].uniq
  refs = keys.flat_map { words_and_consts[it] || [] }
  refs.reject! { |r| defs.any? { |n| n.path == r.path && r.line.between?(n.line, n.end_line) } }
  # A constant reference counts only if it resolves to this module (or cannot be resolved).
  refs.select! { |r| r.kind != :const || mod.nil? || (t = resolve_const(r.const, r.nesting)).nil? || t == mod }
  [name, refs]
end

def kept_namespace?(name, defs)
  mod = resolve(name)
  if mod
    src = begin
      Object.const_source_location(name)
    rescue
      nil
    end
    return "reopened framework or core class" if src.nil? || src.empty? || !src.first.start_with?("#{ROOT}/")
  end
  return "helper" if defs.all? { it.path.start_with?("app/helpers/") }
  return "dynamic name" if DYNAMIC_CONST_SUFFIXES.any? { name.end_with?(it) }
  return "routed controller" if mod.is_a?(Class) && mod < AbstractController::Base &&
    [mod, *mod.descendants].any? { |k| k.respond_to?(:controller_path) && ROUTED.any? { it.start_with?("#{k.controller_path}#") } }
  nil
end

alive = ->(name) { (ns_refs[name] || []).any? { !it.test } }
child_alive = ->(name) { bodies.keys.any? { it.start_with?("#{name}::") && alive.call(it) } }

File.open(File.join(OUT, "namespaces.tsv"), "w") do |f|
  f.puts %w[bucket namespace kind location prod_refs test_refs note].join("\t")
  ns_counts = Hash.new(0)
  bodies.sort.each do |name, defs|
    next if alive.call(name) || child_alive.call(name) || kept_namespace?(name, defs)
    refs = ns_refs[name]
    b = refs.any? ? "9-namespace-test-only" : "9-namespace-unreferenced"
    ns_counts[b] += 1
    mod = resolve(name)
    note = []
    note << "ActiveRecord model: check type/polymorphic columns" if mod.is_a?(Class) && mod < ActiveRecord::Base
    note << "not loaded" unless mod
    note << refs.first(3).map { "#{it.path}:#{it.line}" }.join(" ") if refs.any?
    f.puts [b, name, defs.first.kind, defs.map { "#{it.path}:#{it.line}" }.join(" "), 0, refs.size, note.join("; ")].join("\t")
  end
  log "namespaces: #{ns_counts.sort.to_h.inspect}"
end

counts = rows.filter_map { bucket(it) }.tally.sort.to_h
log "candidates: #{counts.inspect}"
log "kept: #{kept.map { it.first.sub(/ at .*/, "").sub(/ (prefix|suffix) .*/, "") }.tally.sort_by { -it[1] }.to_h.inspect}"
log "unknown-receiver open sends to check by hand: #{PROD_OPEN_SENDS.count { it.receiver == :other }}"
log "wrote #{OUT}/candidates.tsv, namespaces.tsv, kept.tsv and open_sends.tsv"
