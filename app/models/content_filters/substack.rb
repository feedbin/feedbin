module ContentFilters
  class Substack < HTML::Pipeline::Filter
    # `doc = content` created a local that shadowed the `doc` method for the
    # whole body — including the search above it — so the filter read nil and
    # returned nil whenever .body.markup was absent, which fails the next
    # filter in the pipeline with InvalidDocumentException.
    def call
      content = doc.search(".body.markup")
      content.empty? ? doc : content
    end
  end
end