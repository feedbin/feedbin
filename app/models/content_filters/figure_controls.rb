# for example the controls on each image on https://www.thealgorithmicbridge.com
module ContentFilters
  class FigureControls < HTML::Pipeline::Filter
    def call
      doc.tap do
        it.search("figure .image-link-expand svg").each do |element|
          element.remove
        end
      end
    end
  end
end