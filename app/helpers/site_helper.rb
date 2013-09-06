module SiteHelper
  def resizable(column)
    session[:column_widths] ||= {}
    template = 'data-resizable-name="%s"'
    replacements = [sanitize(column)]
    if session[:column_widths][column]
      template << ' style="width: %ipx"'
      replacements << session[:column_widths][column].to_i
    end
    result = template % replacements
    result.html_safe
  end
end
