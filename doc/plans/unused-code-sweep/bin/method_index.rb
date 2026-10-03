# Static index of method definitions and references, built with Prism.
# Plain Ruby: no Rails. dead_methods.rb adds the runtime checks.
#
# A Def knows its lexical owner ("A::B"), its side (instance, singleton, or
# both for module_function / extend self), and its line range.
#
# A Ref is one place that could call a method by name:
#   kind      :call, :super, :symbol, or :word (a word in a string or template)
#   receiver  :none, :self, :const (see .const), :other, or nil for symbol/word
#   side      the self that a receiverless call runs against:
#             :instance, :singleton, :both, or :global (unknown, could be anything)
# Symbols, words, top-level code, and blocks that frameworks run with
# instance_exec are :global, so they count for every method with that name.
require "prism"

class MethodIndex
  Def = Struct.new(:name, :owner, :owner_candidates, :side, :via, :dynamic, :path, :line, :end_line, :test, :nesting)
  Namespace = Struct.new(:name, :kind, :path, :line, :end_line, :test)
  OpenSend = Struct.new(:receiver, :const, :owner, :owner_candidates, :nesting, :side, :path, :line, :test)
  Ref = Struct.new(:name, :kind, :receiver, :const, :owner, :owner_candidates, :nesting, :side, :path, :line, :test)

  # Calls whose block runs with a different self (instance_exec and friends).
  EXEC_BLOCKS = %w[
    instance_eval instance_exec class_eval class_exec module_eval module_exec
    configure draw on_load new define
  ].freeze

  WORD = /[A-Za-z_][A-Za-z0-9_]*[?!]?/
  NAME = /\A[A-Za-z_]/
  # An interpolated string in these places is probably a method name.
  NAME_ARG_CALLS = %i[
    send public_send __send__ try try! respond_to? method public_method instance_method
    public_instance_method alias_method singleton_method
  ].to_set
  NAME_RECEIVER_CALLS = %i[to_sym intern].to_set
  # These define a method; an interpolated name here is not a call.
  DEFINE_CALLS = %i[define_method define_singleton_method].to_set
  # A non-literal name here could call any method of the receiver.
  OPEN_SEND_CALLS = %i[send public_send __send__ try try! method public_method].to_set

  attr_reader :defs, :refs, :patterns, :open_sends, :namespaces

  def initialize
    @defs = []
    @refs = []
    @patterns = []
    @open_sends = []
    @namespaces = []
  end

  def add_ruby(source, path:, test:)
    result = Prism.parse(source, filepath: path)
    result.value.accept(Visitor.new(self, path, test))
    result
  end

  def add_text(source, path:, test:)
    source.each_line.with_index(1) do |text, line|
      text.scrub.scan(WORD) { add_word(it, path, line, test) }
    end
  end

  def add_word(word, path, line, test)
    @refs << Ref.new(name: word, kind: :word, side: :global, path: path, line: line, test: test)
  end

  # One lexical scope: a class or module body, a def body, a block, or the top level.
  Frame = Struct.new(:segments, :side, :in_def, :def_name, :dynamic, :module_function, :singleton_body, :via) do
    def owner = segments.empty? ? nil : segments.join("::")

    def owner_candidates
      full = owner
      compact = segments.each_index.select { segments[it].include?("::") && it.positive? }
      [full, *compact.map { segments[it..].join("::") }].uniq
    end

    def nesting
      (1..segments.size).map { segments.first(it).join("::") }.reverse
    end
  end

  class Visitor < Prism::Visitor
    def initialize(index, path, test)
      @index = index
      @path = path
      @test = test
      @frames = [Frame.new(segments: [], side: :global, in_def: false, dynamic: false)]
      @name_context = 0
      @define_context = 0
      super()
    end

    def visit_class_node(node)
      visit(node.superclass) if node.superclass
      enter_namespace(node) { visit(node.body) if node.body }
    end

    def visit_module_node(node)
      enter_namespace(node) { visit(node.body) if node.body }
    end

    def visit_singleton_class_node(node)
      if node.expression.is_a?(Prism::SelfNode) && frame.owner
        push(frame.to_h.merge(side: :singleton, singleton_body: true, in_def: false)) { visit(node.body) if node.body }
      else
        visit(node.expression)
        push(frame.to_h.merge(side: :global, dynamic: true)) { visit(node.body) if node.body }
      end
    end

    def visit_def_node(node)
      side, owner, dynamic, via = def_placement(node)
      @index.defs << Def.new(
        name: node.name.to_s, owner: owner, owner_candidates: (owner == "Object") ? ["Object"] : frame.owner_candidates,
        side: side, via: via, dynamic: dynamic, path: @path, line: node.location.start_line,
        end_line: node.location.end_line, test: @test, nesting: frame.nesting
      )
      body_side = (owner == "Object") ? :global : side
      push(frame.to_h.merge(side: body_side, in_def: true, def_name: node.name.to_s)) do
        visit(node.parameters) if node.parameters
        visit(node.body) if node.body
      end
    end

    def visit_call_node(node)
      track_module_function(node)
      add_call(node.name.to_s, node.receiver, node.location.start_line)
      add_open_send(node)
      name_context(NAME_RECEIVER_CALLS.include?(node.name)) { visit(node.receiver) } if node.receiver
      if node.arguments
        defining = DEFINE_CALLS.include?(node.name)
        @define_context += 1 if defining
        begin
          name_context(NAME_ARG_CALLS.include?(node.name)) { visit(node.arguments) }
        ensure
          @define_context -= 1 if defining
        end
      end
      return unless node.block

      if node.block.is_a?(Prism::BlockNode)
        push(block_frame(node)) { visit(node.block) }
      else
        visit(node.block)
      end
    end

    def visit_lambda_node(node)
      push(block_frame(nil)) { super }
    end

    def visit_call_operator_write_node(node) = visit_call_write(node)
    def visit_call_or_write_node(node) = visit_call_write(node)
    def visit_call_and_write_node(node) = visit_call_write(node)

    def visit_super_node(node)
      add_super(node)
      super
    end

    def visit_forwarding_super_node(node)
      add_super(node)
      super
    end

    def visit_constant_read_node(node)
      add(name: node.name.to_s, kind: :const, const: node.name.to_s, side: :global, line: node.location.start_line, contextual: true)
      super
    end

    def visit_constant_path_node(node)
      add(name: node.name.to_s, kind: :const, const: constant_name(node), side: :global, line: node.location.start_line, contextual: true)
      super
    end

    def visit_symbol_node(node)
      name = node.unescaped.to_s
      add(name: name, kind: :symbol, side: :global, line: node.location.start_line) unless name.empty?
      super
    end

    def visit_string_node(node)
      node.unescaped.to_s.dup.force_encoding(Encoding::UTF_8).scrub.scan(WORD) do
        @index.add_word(it, @path, node.location.start_line, @test)
      end
      super
    end

    def visit_x_string_node(node)
      node.unescaped.to_s.scrub.scan(WORD) { @index.add_word(it, @path, node.location.start_line, @test) }
      super
    end

    def visit_interpolated_string_node(node)
      collect_patterns(node)
      super
    end

    def visit_interpolated_symbol_node(node)
      collect_patterns(node)
      super
    end

    private

    def frame = @frames.last

    def name_context(on)
      @name_context += 1 if on
      yield
    ensure
      @name_context -= 1 if on
    end

    def push(attrs)
      @frames.push(Frame.new(**attrs))
      yield
    ensure
      @frames.pop
    end

    def enter_namespace(node)
      name = constant_name(node.constant_path)
      segments = name.start_with?("::") ? [name.delete_prefix("::")] : frame.segments + [name]
      @index.namespaces << Namespace.new(name: segments.join("::"), kind: node.is_a?(Prism::ClassNode) ? :class : :module,
        path: @path, line: node.location.start_line, end_line: node.location.end_line, test: @test)
      push(segments: segments, side: :singleton, in_def: false, def_name: nil, dynamic: frame.dynamic, module_function: false, singleton_body: false, via: nil) { yield }
    end

    def constant_name(node)
      case node
      when Prism::ConstantReadNode then node.name.to_s
      when Prism::ConstantPathNode then node.parent ? "#{constant_name(node.parent)}::#{node.name}" : "::#{node.name}"
      else "?"
      end
    end

    # Returns [side, owner, dynamic, via] for a def in the current frame.
    def def_placement(node)
      owner = frame.owner || "Object"
      dynamic = frame.dynamic || frame.in_def
      side =
        if node.receiver.is_a?(Prism::SelfNode) then :singleton
        elsif node.receiver then (dynamic = true) && :singleton
        elsif frame.via == :class_methods || frame.singleton_body then :singleton
        elsif frame.module_function then :both
        else :instance
        end
      [side, owner, dynamic, frame.via]
    end

    def track_module_function(node)
      return if node.receiver || frame.in_def || !frame.owner
      args = node.arguments&.arguments || []
      if node.name == :module_function && args.empty?
        frame.module_function = true
      elsif node.name == :extend && args.any? { it.is_a?(Prism::SelfNode) }
        frame.module_function = true
      end
    end

    def block_frame(call)
      name = call&.name.to_s
      base = frame.to_h
      if EXEC_BLOCKS.include?(name)
        base.merge(side: :global, dynamic: true)
      elsif name == "class_methods" && call.receiver.nil? && frame.owner && !frame.in_def
        base.merge(side: :singleton, via: :class_methods)
      elsif frame.owner.nil? || frame.side == :global
        base.merge(side: :global, dynamic: true)
      elsif frame.in_def
        base.merge(dynamic: true)
      else
        base.merge(side: :both, dynamic: true)
      end
    end

    def receiver_kind(receiver)
      case receiver
      when nil then [:none, nil]
      when Prism::SelfNode then [:self, nil]
      when Prism::ConstantReadNode, Prism::ConstantPathNode then [:const, constant_name(receiver)]
      else [:other, nil]
      end
    end

    def add_call(name, receiver, line)
      return unless name.match?(NAME)
      kind, const = receiver_kind(receiver)
      add(name: name, kind: :call, receiver: kind, const: const, side: frame.side, line: line, contextual: true)
    end

    def add_open_send(node)
      return unless OPEN_SEND_CALLS.include?(node.name)
      first = node.arguments&.arguments&.first
      literal = [Prism::SymbolNode, Prism::StringNode, Prism::InterpolatedSymbolNode, Prism::InterpolatedStringNode]
      return if first.nil? || literal.any? { first.is_a?(it) }
      kind, const = receiver_kind(node.receiver)
      @index.open_sends << OpenSend.new(receiver: kind, const: const, owner: frame.owner, owner_candidates: frame.owner_candidates,
        nesting: frame.nesting, side: frame.side, path: @path, line: node.location.start_line, test: @test)
    end

    def visit_call_write(node)
      line = node.location.start_line
      add_call(node.read_name.to_s, node.receiver, line)
      add_call(node.write_name.to_s, node.receiver, line)
      visit(node.receiver) if node.receiver
      visit(node.value)
    end

    def add_super(node)
      return unless frame.def_name
      add(name: frame.def_name, kind: :super, receiver: :none, side: frame.side, line: node.location.start_line, contextual: true)
    end

    def add(name:, kind:, side:, line:, receiver: nil, const: nil, contextual: false)
      owner = contextual ? frame.owner : nil
      candidates = contextual ? frame.owner_candidates : nil
      nesting = contextual ? frame.nesting : nil
      @index.refs << Ref.new(name: name, kind: kind, receiver: receiver, const: const, owner: owner, owner_candidates: candidates,
        nesting: nesting, side: side, path: @path, line: line, test: @test)
    end

    # "format_#{x}" gives prefix "format_"; :"#{x}_url" gives suffix "_url".
    # Strength is :call for symbols, send-like arguments and .to_sym receivers,
    # :loose for any other string. A bare "=", "?" or "!" suffix counts only as :call.
    def collect_patterns(node)
      return if @define_context.positive?
      strength = (node.is_a?(Prism::InterpolatedSymbolNode) || @name_context.positive?) ? :call : :loose
      parts = node.parts
      parts.each_with_index do |part, i|
        next unless part.is_a?(Prism::StringNode)
        text = part.unescaped.to_s.dup.force_encoding(Encoding::UTF_8).scrub
        if parts[i + 1].is_a?(Prism::EmbeddedStatementsNode) && (frag = text[/[a-z0-9_]+\z/i]) && frag.match?(/\A[a-z0-9_]*[a-z][a-z0-9_]*_\z/i)
          @index.patterns << [:prefix, frag, @path, part.location.start_line, strength]
        end
        next unless i.positive? && parts[i - 1].is_a?(Prism::EmbeddedStatementsNode)
        frag = text[/\A[a-z0-9_]*[?!=]?/i]
        if frag.match?(/\A_[a-z0-9_]*[a-z][a-z0-9_]*[?!=]?\z/i) || (strength == :call && %w[= ? !].include?(frag))
          @index.patterns << [:suffix, frag, @path, part.location.start_line, strength]
        end
      end
    end
  end
end
