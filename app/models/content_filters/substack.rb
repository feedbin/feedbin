module ContentFilters
  class Substack < HTML::Pipeline::Filter
    def call
      content = doc.search(".body.markup")
      unless content.empty?
        doc = content
      end
      doc
    end
  end
end