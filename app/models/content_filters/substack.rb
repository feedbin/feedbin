module ContentFilters
  class Substack < HTML::Pipeline::Filter
    # `doc = content` created a local that shadowed the `doc` method for the
    # whole body — including the search above it — so the filter read nil and
    # returned nil whenever .body.markup was absent, which fails the next
    # filter in the pipeline with InvalidDocumentException.
    #
    # The body replaces the fragment's children rather than being returned
    # as a NodeSet: the filters after this one query ./descendant::, which on
    # a NodeSet skips the set's own nodes, so the body's style and class
    # would survive.
    def call
      content = doc.search(".body.markup")
      doc.children = content unless content.empty?
      doc
    end
  end
end
