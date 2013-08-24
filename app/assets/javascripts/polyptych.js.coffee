window.feedbin ?= {}

jQuery ->
  new feedbin.Polyptych()
    
class feedbin.Polyptych
  constructor: ->
    if feedbin.data?.polyptychUrl?
      @app = feedbin.data.polyptychUrl
      @cdn = feedbin.data.polyptychCdn
      @stylesheetUrl = "/panels/#{feedbin.data.feedHostnamesHash}.css"
      @checkCompleteUrl = "#{@app}/panels/#{feedbin.data.feedHostnamesHash}/status"
      @createStylesheetUrl = "#{@app}/panels.json"
      if feedbin.data.faviconComplete
        @addStylesheet(@cdn + @stylesheetUrl)
      else
        @checkIfStylesExist()
    
  checkIfStylesExist: =>
    $.ajax
      type: "GET",
      url: @checkCompleteUrl
      success: (data) =>
        if data.complete
          @addStylesheet(@cdn + @stylesheetUrl)
          $.post feedbin.data.markFaviconCompletePath
        else if data.exists
          @addStylesheet(@app + @stylesheetUrl)
        else
          @createStylesheet()

  addStylesheet: (url) ->
    link = $ '<link>',
      type: 'text/css'
      rel: 'stylesheet'
      href: url
    $("head").append link
  
  createStylesheet: =>
    $.ajax
      type: 'POST'
      url: @createStylesheetUrl
      contentType: "application/json; charset=utf-8"
      dataType: 'json'
      data: JSON.stringify
        hostnames: feedbin.data.feedHostnames.split(',')
      success: =>
        @addStylesheet(@app + @stylesheetUrl)
      error: (e) =>
        if 302 == e.status
          @addStylesheet(@app + @stylesheetUrl)
