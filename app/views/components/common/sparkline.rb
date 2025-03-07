class Common::Sparkline < Phlex::SVG
  def initialize(sparkline:, theme:)
    @sparkline = sparkline
    @theme = theme
  end

  def view_template
    svg(width: @sparkline.width, height: @sparkline.height, stroke_width: @sparkline.stroke) do
      linearGradient(id: "gradient", x1: "0", x2: "0", y1: "0", y2: "1") do
        stop(class: @theme ? "[stop-color:rgb(var(--color-500))]" : "[stop-color:rgb(var(--color-green-600))]", offset: "0%", stop_opacity: "0.75")
        stop(class: @theme ? "[stop-color:rgb(var(--color-500))]" : "[stop-color:rgb(var(--color-green-600))]", offset: "100%", stop_opacity: "0.02")
      end

      polygon(points: @sparkline.fill, fill: "url(#gradient)")

      polyline(
        class: [
          ("fill-transparent [stroke-linejoin:round] [stroke-linecap:round]"),
          (@theme ? "stroke-[rgb(var(--color-400))]" : "stroke-[rgb(var(--color-green-600))]")
        ],
        points: @sparkline.line
      )
    end
  end
end
