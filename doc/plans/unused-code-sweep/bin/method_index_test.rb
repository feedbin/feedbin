# Fixture tests for method_index.rb.
# Run: ruby doc/plans/unused-code-sweep/bin/method_index_test.rb
require "minitest/autorun"
require_relative "method_index"

class MethodIndexTest < Minitest::Test
  def index(source, path: "app/models/x.rb", test: false)
    MethodIndex.new.tap { it.add_ruby(source, path: path, test: test) }
  end

  def defn(idx, name)
    found = idx.defs.select { it.name == name }
    assert_equal 1, found.size, "expected one def named #{name}, got #{found.inspect}"
    found.first
  end

  def refs(idx, name) = idx.refs.select { it.name == name }

  # Owners and sides

  def test_nested_modules_give_the_full_owner_name
    idx = index("module A\n  class B\n    def x; end\n  end\nend\n")
    assert_equal "A::B", defn(idx, "x").owner
    assert_equal :instance, defn(idx, "x").side
  end

  def test_compact_class_path_inside_a_module_lists_both_resolutions
    idx = index("module X\n  class A::B\n    def x; end\n  end\nend\n")
    assert_equal ["X::A::B", "A::B"], defn(idx, "x").owner_candidates
  end

  def test_def_self_is_singleton
    idx = index("class A\n  def self.x; end\nend\n")
    assert_equal :singleton, defn(idx, "x").side
  end

  def test_class_shovel_self_is_singleton
    idx = index("class A\n  class << self\n    def x; end\n  end\nend\n")
    assert_equal :singleton, defn(idx, "x").side
  end

  def test_module_function_and_extend_self_give_both_sides
    idx = index("module A\n  module_function\n  def x; end\nend\nmodule B\n  extend self\n  def y; end\nend\n")
    assert_equal :both, defn(idx, "x").side
    assert_equal :both, defn(idx, "y").side
  end

  def test_concern_class_methods_block_is_singleton_of_the_concern
    idx = index("module C\n  extend ActiveSupport::Concern\n  class_methods do\n    def x; end\n  end\nend\n")
    d = defn(idx, "x")
    assert_equal "C", d.owner
    assert_equal :singleton, d.side
    assert_equal :class_methods, d.via
    refute d.dynamic
  end

  def test_def_inside_an_included_block_is_dynamic
    idx = index("module C\n  included do\n    def x; end\n  end\nend\n")
    assert defn(idx, "x").dynamic
  end

  def test_def_records_its_line_range
    idx = index("class A\n  def x\n    1\n  end\nend\n")
    assert_equal [2, 4], [defn(idx, "x").line, defn(idx, "x").end_line]
  end

  def test_top_level_def_is_owned_by_object
    idx = index("def helper_thing; end\n", path: "lib/tasks/a.rake")
    assert_equal "Object", defn(idx, "helper_thing").owner
  end

  # Call references

  def test_receiver_kinds
    idx = index("class A\n  def run\n    a1\n    self.a2\n    Foo::Bar.a3\n    thing.a4\n  end\nend\n")
    assert_equal :none, refs(idx, "a1").first.receiver
    assert_equal :self, refs(idx, "a2").first.receiver
    assert_equal :const, refs(idx, "a3").first.receiver
    assert_equal "Foo::Bar", refs(idx, "a3").first.const
    assert_equal :other, refs(idx, "a4").first.receiver
  end

  def test_call_in_an_instance_method_has_instance_context
    r = refs(index("module M\n  class A\n    def run; go; end\n  end\nend\n"), "go").first
    assert_equal "M::A", r.owner
    assert_equal :instance, r.side
    assert_equal ["M::A", "M"], r.nesting
  end

  def test_call_keeps_the_owner_candidates_of_its_context
    r = refs(index("module X\n  class A::B\n    def run; go; end\n  end\nend\n"), "go").first
    assert_equal ["X::A::B", "A::B"], r.owner_candidates
  end

  def test_call_in_a_class_body_has_singleton_context
    assert_equal :singleton, refs(index("class A\n  go\nend\n"), "go").first.side
  end

  def test_call_in_a_lambda_or_block_in_a_class_body_has_both_contexts
    idx = index("class A\n  scope :s, -> { go1 }\n  before_save do\n    go2\n  end\nend\n")
    assert_equal :both, refs(idx, "go1").first.side
    assert_equal :both, refs(idx, "go2").first.side
  end

  def test_block_in_an_instance_method_keeps_the_instance_context
    r = refs(index("class A\n  def run\n    items.each { go }\n  end\nend\n"), "go").first
    assert_equal :instance, r.side
  end

  def test_instance_exec_style_blocks_are_global
    idx = index("class A\n  def run\n    obj.instance_eval { go1 }\n  end\nend\nRails.application.configure do\n  go2\nend\n")
    assert_equal :global, refs(idx, "go1").first.side
    assert_equal :global, refs(idx, "go2").first.side
  end

  def test_top_level_calls_are_global
    assert_equal :global, refs(index("go\n", path: "config/routes.rb"), "go").first.side
  end

  def test_attribute_writes_reference_the_setter
    idx = index("class A\n  def run\n    self.name = 1\n    self.count ||= 0\n  end\nend\n")
    assert_equal :self, refs(idx, "name=").first.receiver
    refute_empty refs(idx, "count=")
    refute_empty refs(idx, "count")
  end

  def test_super_references_the_enclosing_method_name
    r = refs(index("class A < B\n  def save\n    super\n  end\nend\n"), "save").first
    assert_equal :super, r.kind
    assert_equal :none, r.receiver
    assert_equal :instance, r.side
  end

  # Symbols, strings and patterns

  def test_symbols_and_string_words_are_global
    idx = index("class A\n  before_action :load_thing\n  def run; send(\"other_thing\"); end\nend\n")
    sym = refs(idx, "load_thing").first
    assert_equal [:symbol, nil, :global], [sym.kind, sym.receiver, sym.side]
    word = refs(idx, "other_thing").first
    assert_equal [:word, :global], [word.kind, word.side]
  end

  def test_comments_are_not_references
    assert_empty refs(index("class A\n  # call go here\nend\n"), "go")
  end

  def test_interpolated_names_give_prefix_and_suffix_patterns
    idx = index("class A\n  def run\n    send(\"format_\#{x}\")\n    send(:\"\#{type}_url\")\n    \"icon-\#{y}\"\n  end\nend\n")
    assert_includes idx.patterns.map { it.first(2) }, [:prefix, "format_"]
    assert_includes idx.patterns.map { it.first(2) }, [:suffix, "_url"]
    refute idx.patterns.any? { it[1].include?("icon") }
  end

  def test_patterns_need_an_underscore_boundary
    idx = index("a = \"\#{x}s\"\nb = \"media\#{x}\"\nc = \"\#{x}feed\"\n")
    assert_empty idx.patterns
  end

  def test_pattern_strength_depends_on_the_context
    idx = index(<<~RUBY)
      send("format_\#{x}")
      "cast_\#{x}".to_sym
      :"\#{x}_url"
      "tweet_\#{id}"
    RUBY
    strength = idx.patterns.to_h { [it[1], it[4]] }
    assert_equal({"format_" => :call, "cast_" => :call, "_url" => :call, "tweet_" => :loose}, strength)
  end

  def test_bare_setter_and_predicate_suffixes_count_only_in_a_call_context
    idx = index("public_send(\"\#{key}=\", v)\nsend(\"\#{x}?\")\n\"\#{a}=\#{b}\"\n")
    assert_equal [[:suffix, "=", :call], [:suffix, "?", :call]], idx.patterns.map { [it[0], it[1], it[4]] }
  end

  def test_define_method_names_are_definitions_not_patterns
    idx = index("class A\n  [:x].each do |item|\n    define_method \"\#{item}?\".to_sym, -> { 1 }\n    define_method(\"get_\#{item}\") { 2 }\n  end\nend\n")
    assert_empty idx.patterns
  end

  def test_send_with_a_non_literal_name_is_an_open_send
    idx = index("class A\n  def run\n    MarketingMailer.send(@message, 1)\n    send(name)\n    thing.public_send(:literal)\n  end\nend\n")
    sends = idx.open_sends.map { [it.receiver, it.const, it.owner, it.side] }
    assert_equal [[:const, "MarketingMailer", "A", :instance], [:none, nil, "A", :instance]], sends
  end

  def test_absolute_constant_receiver_keeps_the_leading_colons
    r = refs(index("module C\n  class Image\n    def run; ::Image.go; end\n  end\nend\n"), "go").first
    assert_equal "::Image", r.const
  end

  def test_interpolated_string_with_invalid_bytes_does_not_raise
    idx = index("x = \"\\xff_name_\#{y}\"\n")
    assert_includes idx.patterns.map { it.first(2) }, [:prefix, "_name_"]
  end

  # Namespaces and constant references

  def test_namespaces_record_full_name_and_line_range
    idx = index("module A\n  class B < Base\n    X = 1\n  end\nend\n")
    assert_equal [["A", 1, 5], ["A::B", 2, 4]], idx.namespaces.map { [it.name, it.line, it.end_line] }
  end

  def test_constant_reads_and_paths_are_const_refs
    idx = index("class A < Base\n  def run\n    Foo::Bar.go\n    ::Baz\n  end\nend\n")
    names = idx.refs.select { it.kind == :const }.map(&:name)
    assert_equal %w[Base Foo Bar Baz].sort, names.sort
  end

  def test_const_refs_keep_the_written_path_and_nesting
    idx = index("module M\n  class A\n    def run\n      Foo::Bar\n      ::Baz\n    end\n  end\nend\n")
    by_name = idx.refs.select { it.kind == :const }.to_h { [it.name, it] }
    assert_equal "Foo::Bar", by_name["Bar"].const
    assert_equal "Foo", by_name["Foo"].const
    assert_equal "::Baz", by_name["Baz"].const
    assert_equal ["M::A", "M"], by_name["Bar"].nesting
  end

  def test_the_defining_constant_is_not_a_reference
    idx = index("module A\n  class B\n  end\nend\n")
    assert_empty idx.refs.select { it.kind == :const }
  end

  def test_text_adds_global_words
    idx = MethodIndex.new
    idx.add_text("<%= go_there %> some_words", path: "app/views/a.html.erb", test: false)
    r = refs(idx, "go_there").first
    assert_equal [:word, :global], [r.kind, r.side]
  end

  def test_test_flag_is_kept_on_refs
    assert refs(index("go\n", path: "test/a_test.rb", test: true), "go").first.test
  end
end
