window.feedbin ?= {}

(($) ->

  $.fn.isAfter = (sel) ->
    @prevAll().filter(sel).length != 0

  $.fn.isBefore = (sel) ->
    @nextAll().filter(sel).length != 0

  return
) jQuery

$.extend feedbin,

  messageTimeout: null
  swipe: false
  panel: 1
  colorHash: new ColorHash
    lightness: [.3,.4,.5,.6,.7]
    saturation: [.7,.8]

  fonts: (font) ->
    if !feedbin.fontsLoaded && feedbin.data && feedbin.data.font_stylesheet
      if $.inArray(font, ["sans-serif-1", "sans-serif-2", "serif-1", "serif-2"]) != -1
        loadCSS(feedbin.data.font_stylesheet)
        feedbin.fontsLoaded = true

  faviconColors: (target) ->
    $(".favicon-default", target).each ->
      host = $(@).data("host")
      color = feedbin.colorHash.hex(host)
      $(@).css
        "background-color": color

  calculateColor: (backgroundColor, foregroundColor) ->
    canvas = document.createElement('canvas')
    canvas.style.display = 'none'
    canvas.width = 10
    canvas.height = 10
    document.body.appendChild canvas

    context = canvas.getContext('2d')
    context.fillStyle = backgroundColor
    context.fillRect 0, 0, 10, 10
    context.fillStyle = foregroundColor
    context.fillRect 0, 0, 10, 10
    data = context.getImageData(1, 1, 1, 1)
    "rgba(#{data.data[0]}, #{data.data[1]}, #{data.data[2]}, #{data.data[3]})"

  setNativeTitleColor: (rgb, timeout = 1) ->
    ctx = document.createElement('canvas').getContext('2d')
    ctx.strokeStyle = rgb
    hex = ctx.strokeStyle
    feedbin.themeColorHex = hex
    setTimeout ( ->
      feedbin.nativeMessage("performAction", { action: "titleColor", color: hex })
    ), timeout

  nativeMessage: (name, data) ->
    if typeof(webkit) != "undefined" && webkit.messageHandlers && webkit.messageHandlers.turbolinksDemo
      webkit.messageHandlers.turbolinksDemo.postMessage
        name: name
        data: data

  scrollBars: ->
    width = 100

    outer = $('<div><div></div></div>').css
      "width": "#{width}px"
      "height": "100px"
      "overflow-y": "scroll"
      "position": "absolute"
      "top": "-99999px"
      "left": "-99999px"

    inner = outer.find('div').css
      "width": "100%"
      "height": "200px"

    $("body").append(outer)

    result = inner.outerWidth() < width

    outer.remove()

    result

  scrollToTop: ->
    element = null
    if feedbin.panel == 1
      element = $(".feeds")
    else if feedbin.panel == 2
      element = $(".entries")
    else if feedbin.panel == 3
      element = $(".entry-content")

    if element
      element.css
        "-webkit-overflow-scrolling": "auto"
      element.animate {scrollTop: 0}, {
        duration: 150,
        complete: ()->
          element.css
            "-webkit-overflow-scrolling": "touch"
      }


  toggleDiff: ->
    $('[data-behavior~=diff_view_changes]').toggleClass("hide")
    $('[data-behavior~=diff_view_latest]').toggleClass("hide")

    $('[data-behavior~=diff_latest]').toggleClass("hide")
    $('[data-behavior~=diff_content]').toggleClass("hide")

  drawBarCharts: ->
    $('[data-behavior~=line_graph]').each ()->
      feedbin.drawBarChart(@, $(@).data('values'))

  modalContent: (html, target) ->
    $(".#{target} .modal-body").html(html);

  showFeedList: ->
    $('[data-behavior~=feeds_target]').removeClass('hide')
    $('[data-behavior~=feeds_target]').addClass('show')

  mobileView: ->
    if $(window).width() <= 550
      true
    else
      false

  showPanel: (panel, state = true) ->
    feedbin.panel = panel
    if panel == 1
      if feedbin.mobileView()
        window.history.replaceState({panel: 1}, document.title, "/");
      $('body').addClass('nothing-selected').removeClass('feed-selected entry-selected')
      if feedbin.swipe
        $('.app-wrap').animate({scrollLeft: 0}, {duration: 150})
    else if panel == 2
      if state && feedbin.mobileView()
        window.history.pushState({panel: 2}, document.title, "/");
      $('body').addClass('feed-selected').removeClass('nothing-selected entry-selected')
      if feedbin.swipe
        offset = $('.entries-column')[0].offsetLeft
        $('.app-wrap').animate({scrollLeft: offset}, {duration: 150})
    else if panel == 3
      if state && feedbin.mobileView()
        window.history.pushState({panel: 3}, document.title, "/");
      $('body').addClass('entry-selected').removeClass('nothing-selected feed-selected')
      if feedbin.swipe
        offset = $('.entry-column')[0].offsetLeft
        $('.app-wrap').animate({scrollLeft: offset}, {duration: 150})


  showNotification: (text, timeout = 3000, href = '', error = false) ->

    clearTimeout(feedbin.messageTimeout)

    messages = $('[data-behavior~=messages]')
    if error == true
      messages.addClass('error')
    else
      messages.removeClass('error')

    if href == ''
      messages.removeAttr('href')
    else
      messages.attr('href', href)

    messages.text(text)
    messages.addClass('show')
    messages.addClass('slide')
    feedbin.messageTimeout = setTimeout ( ->
      messages.removeClass('slide')
      setTimeout ( ->
        messages.removeClass('show')
      ), 200
    ), timeout

  hideNotification: ->
    messages = $('[data-behavior~=messages]')
    messages.removeClass('slide')
    setTimeout ( ->
      messages.removeClass('show')
    ), 200


  updateEntries: (entries, header) ->
    $('.entries ul').html(entries)
    $('.entries-header').html(header)

  appendEntries: (entries, header) ->
    $('.entries ul').append(entries)
    $('.entries-header').html(header)

  updatePager: (html) ->
    $('[data-behavior~=pagination]').html(html)

  entryChanged: ->
    !feedbin.previousEntry || !feedbin.previousEntry.container.is(feedbin.selectedEntry.container)

  animateEntryContent: (content) ->
    innerContent = $('[data-behavior~=inner_content_target]')

    if $(feedbin.selectedEntry.container.closest("li")).isAfter(feedbin.previousEntry.container.closest("li"))
      next = $('<div class="next-entry load-next-entry"></div>')
      transitionClass = "slide-up"
    else
      next = $('<div class="previous-entry load-next-entry"></div>')
      transitionClass = "slide-down"

    next.html(content)

    next.insertAfter(innerContent)

    setTimeout ( ->
      next.removeClass("load-next-entry")
      $(".entry-content", innerContent).addClass(transitionClass)
    ), 1

    setTimeout ( ->
      next.removeClass("next-entry")
      next.removeClass("previous-entry")
      next.attr("data-behavior", "inner_content_target")
      innerContent.remove()
    ), 200

  shouldAnimate: ->
    offset = $('.entry-column')[0].offsetLeft
    scroll = $('.app-wrap')[0].scrollLeft

    if feedbin.previousEntry && feedbin.mobileView()
      if scroll > 0
        if offset == scroll
          true
      else if feedbin.panel == 3
        true

  updateEntryContent: (meta, content = "") ->
    feedbin.closeEntryBasement(0)
    metaTarget = $('[data-behavior~=entry_meta_target]')
    innerContent = $('[data-behavior~=inner_content_target]')

    metaTarget.html(meta)

    if meta == ""
      feedbin.previousEntry = null
      feedbin.selectedEntry = null
      $('.entry-column').removeClass("has-content")
      innerContent.html("")
    else
      $('.entry-column').addClass("has-content")

    if !feedbin.entryChanged()
      innerContent.html(content)
    else if feedbin.shouldAnimate()
      feedbin.animateEntryContent(content)
    else
      innerContent.html(content)

  updateFeeds: (feeds) ->
    $('[data-behavior~=feeds_target]').html(feeds)

  clearEntries: ->
    $('[data-behavior~=entries_target]').html('')

  clearEntry: ->
    feedbin.updateEntryContent('')

  syntaxHighlight: ->
    $('[data-behavior~=entry_content_target] pre code').each (i, e) ->
      hljs.highlightBlock(e)

  audioVideo: (selector = "entry_final_content") ->
    $("[data-behavior~=#{selector}] audio").mediaelementplayer
      stretching: 'responsive'
      features: ['playpause', 'current', 'progress', 'duration', 'tracks', 'fullscreen']
    $("video").mediaelementplayer
      stretching: 'responsive'
      features: ['playpause', 'current', 'progress', 'duration', 'tracks', 'fullscreen']


  footnotes: ->
    $.bigfoot
      scope: '[data-behavior~=entry_content_wrap]'
      actionOriginalFN: 'ignore'
      buttonMarkup: "<div class='bigfoot-footnote__container'> <button class=\"bigfoot-footnote__button\" id=\"{{SUP:data-footnote-backlink-ref}}\" data-footnote-number=\"{{FOOTNOTENUM}}\" data-footnote-identifier=\"{{FOOTNOTEID}}\" alt=\"See Footnote {{FOOTNOTENUM}}\" rel=\"footnote\" data-bigfoot-footnote=\"{{FOOTNOTECONTENT}}\"> {{FOOTNOTENUM}} </button></div>"

  blogContent: (content) ->
    content = $.parseJSON(content)
    $('.blog-post').text(content.title);
    $('.blog-post').attr('href', content.url);

  isRead: (entryId) ->
    feedbin.Counts.get().isRead(entryId)

  imagePlaceholders: (element) ->
    image = new Image()
    placehold = element.children[0]
    element.className += ' is-loading'

    image.onload = ->
      element.className = element.className.replace('is-loading', 'is-loaded')
      element.replaceChild(image, placehold)

    image.onerror = ->
      element.style.display = "none"

    for attr in placehold.attributes
      if (attr.name.match(/^data-/))
        image.setAttribute(attr.name.replace('data-', ''), attr.value)

  loadEntryImages: ->
    if $("body").hasClass("entries-image-1")
      placeholders = document.querySelectorAll('.entry-image')
      for placeholder in placeholders
        feedbin.imagePlaceholders(placeholder)

  preloadAssets: (id) ->
    id = parseInt(id)
    if feedbin.entries[id] && !_.contains(feedbin.preloadedImageIds, id)
      content = $(feedbin.entries[id].inner_content)

      feedbin.formatIframes(content.find("[data-iframe-src]"))
      feedbin.formatTweets(content)
      feedbin.formatInstagram(content)

      content.find("img[data-camo-src][data-canonical-src]").each ->
        if feedbin.data.proxy_images
          src = 'camo-src'
        else
          src = 'canonical-src'
        $(@).attr("src", $(@).data(src))
      feedbin.preloadedImageIds.push(id)

  localizeTime: ->
    now = new Date()
    $("time.timeago").each ->
      datePublished = $(@).attr('datetime')
      datePublished = new Date(datePublished)
      if datePublished > now
        $(@).text('the future')
      else if (now - datePublished) < feedbin.ONE_DAY * 7
        $(@).timeago()
      else if datePublished.getFullYear() == now.getFullYear()
        $(@).text(datePublished.format("%e %b"))
      else
        $(@).text(datePublished.format("%e %b %Y"))

  entryTime: ->
    $(".post-meta time").each ->
      date = $(@).attr('datetime')
      date = new Date(date)
      $(@).text(date.format("%B %e, %Y at %l:%M %p"))

  applyUserTitles: ->
    textarea = document.createElement("textarea")
    $('[data-behavior~=user_title]').each ->
      element = $(@)
      feed = element.data('feed-id')
      if (feed of feedbin.data.user_titles)
        newTitle = feedbin.data.user_titles[feed]
        if element.prop('tagName') == "INPUT"
          textarea.innerHTML = newTitle
          element.val(textarea.value)
        else
          element.html(newTitle)

  queryString: (name) ->
    name = name.replace(/[\[]/, "\\[").replace(/[\]]/, "\\]")
    regexS = "[\\?&]" + name + "=([^&#]*)"
    regex = new RegExp(regexS)
    results = regex.exec(window.location.search)
    if results?
      decodeURIComponent results[1].replace(/\+/g, " ")
    else
      null

  openLinkInBackground: (href) ->
    anchor = document.createElement("a")
    anchor.href = href
    event = document.createEvent("MouseEvents")
    event.initMouseEvent "click", true, true, window, 0, 0, 0, 0, 0, true, false, false, true, 0, null
    anchor.dispatchEvent event

  autocomplete: (element) ->
    target = $("[data-behavior~=tag_completions]").first()
    element.autocomplete
      serviceUrl: feedbin.data.tags_path
      appendTo: target
      delimiter: /(,)\s*/

  preloadEntries: (entry_ids, forcePreload = false) ->
    cachedIds = []
    for key of feedbin.entries
      cachedIds.push key * 1
    if !forcePreload
      entry_ids = _.difference(entry_ids, cachedIds)
    if entry_ids.length > 0
      $.getJSON feedbin.data.preload_entries_path, {ids: entry_ids.join(',')}, (data) ->
        $.extend feedbin.entries, data
        feedbin.preloadAssets(entry_ids[0])

  readability: () ->
    feedId = feedbin.selectedEntry.feed_id
    entryId = feedbin.selectedEntry.id

    if feedbin.data.readability_settings[feedId] == true && feedbin.data.sticky_readability
      feedbin.automaticSubmit = true

      loadingTemplate = $('[data-behavior~=readability_loading]').html()

      feedbin.previousContent = $("[data-entry-id=#{entryId}] [data-behavior~=entry_content_wrap]").html()

      $('[data-behavior~=entry_content_wrap]').html(loadingTemplate)
      $('[data-behavior~=toggle_content_view]').submit()

  resetScroll: ->
    $('.entry-content').prop('scrollTop', 0)

  fitVids: (target) ->
    target.fitVids({ customSelector: "iframe"});

  randomNumber: ->
    Math.floor(Math.random() * 1000)

  embed: (items, embed_url, urlFinder) ->
    if items.length > 0
      items.each ->
        item = $(@)
        url = urlFinder(item)
        embedElement = feedbin.embeds["#{url}"]
        if embedElement
          item.replaceWith(embedElement.clone())
        else if url
          id = feedbin.randomNumber()
          item.attr("id", id)
          $.get(embed_url, {url: url, dom_id: id}).fail ->
            item.css({display: "block"})


  formatTweets: (target = "[data-behavior~=entry_content_wrap]") ->
    items = $('blockquote.twitter-tweet', target)

    urlFinder = (item) ->
      $("a", item).last().attr("href")

    feedbin.embed(items, feedbin.data.twitter_embed_path, urlFinder)


  formatInstagram: (target = "[data-behavior~=entry_content_wrap]") ->
    items = $('blockquote.instagram-media', target)

    urlFinder = (item) ->
      item.data("instgrmPermalink") || $("a", item).last().attr("href")

    feedbin.embed(items, feedbin.data.instagram_embed_path, urlFinder)

  checkType: ->
    element = $('.entry-final-content')
    if element.length > 0
      tag = element.children().get(0)
      if tag
        node = tag.nodeName
        if node == "TABLE"
          $('.entry-type-default').removeClass("entry-type-default").addClass("entry-type-newsletter");

  formatIframes: (selector) ->
    selector.each ->
      container = $(@)
      id = container.attr("id")

      embedElement = feedbin.embeds["#{id}"]
      if embedElement
        container.replaceWith(embedElement.clone())
      else
        container.html $("<div class='inline-spinner'>Loading embed from #{container.data("iframe-host")}…</div>")
        $.get container.data("iframe-embed-url")

  formatImages: ->
    $("img[data-camo-src]").each ->
      img = $(@)

      if feedbin.data.proxy_images
        src = 'camo-src'
      else
        src = 'canonical-src'

      actualSrc = img.data(src)
      if actualSrc?
        img.attr("src", actualSrc)

      load = ->
        width = img.get(0).naturalWidth
        if width > 528 && img.parents(".modal").length == 0
          img.addClass("full-width")
        img.addClass("show")

      if img.get(0).complete
        load()

      img.on 'load', (event) ->
        load()

      if img.is("[src*='feeds.feedburner.com'], [data-canonical-src*='feeds.feedburner.com']")
        img.addClass('hide')

  preloadSiblings: ->
    selected = feedbin.selectedEntry.container.closest('li')
    siblings = selected.nextAll().slice(0,4).add(selected.prevAll().slice(0,4))
    siblings.each ->
      id = $(@).data('entry-id')
      feedbin.preloadAssets(id)

  formatEntryContent: (entryId, resetScroll=true, readability=true) ->
    if feedbin.readabilityXHR != null
      feedbin.readabilityXHR.abort()
      feedbin.readabilityXHR = null

    feedbin.applyStarred(entryId)
    if resetScroll
      feedbin.resetScroll
    if readability
      feedbin.readability()
    try
      feedbin.formatIframes($("[data-iframe-src]"))
      feedbin.playState()
      feedbin.timeRemaining(entryId)
      feedbin.syntaxHighlight()
      feedbin.footnotes()
      feedbin.nextEntryPreview()
      feedbin.audioVideo()
      feedbin.entryTime()
      feedbin.applyUserTitles()
      feedbin.formatTweets()
      feedbin.formatInstagram()
      feedbin.formatImages()
      feedbin.checkType()
      feedbin.preloadSiblings()
    catch error
      if 'console' of window
        console.log error

  formatLinkContents: ->
    try
      feedbin.formatIframes($("[data-iframe-src]"))
      feedbin.audioVideo("view_link_markup_wrap")
      feedbin.formatTweets("[data-behavior~=view_link_markup_wrap]")
      feedbin.formatInstagram("[data-behavior~=view_link_markup_wrap]")
      feedbin.formatImages()
    catch error
      if 'console' of window
        console.log error

  refresh: ->
    if feedbin.data
      $.get(feedbin.data.auto_update_path)

  shareOpen: ->
    $('[data-behavior~=toggle_share_menu]').parents('.dropdown-wrap').hasClass('open')

  updateFontSize: (direction) ->
    fontContainer = $("[data-font-size]")
    currentFontSize = fontContainer.data('font-size')
    if direction == 'increase'
      newFontSize = currentFontSize + 1
    else
      newFontSize = currentFontSize - 1
    if feedbin.data.font_sizes[newFontSize]
      fontContainer.removeClass("font-size-#{currentFontSize}")
      fontContainer.addClass("font-size-#{newFontSize}")
      fontContainer.data('font-size', newFontSize)

  matchHeights: (elements) ->
    height = 0
    $.each elements, (index, element) ->
      $(element).css({'height': ''})
      outerHeight = $(element).outerHeight()
      if outerHeight > height
        height = outerHeight

    elements.css
      height: height

  disableMarkRead: () ->
    feedbin.markReadData = {}
    $('[data-behavior~=mark_all_as_read]').attr('disabled', 'disabled')

  log: (input) ->
    console.log input

  markRead: () ->
    feedbin.showPanel(1);
    $('.entries li').addClass('read')
    feedbin.markReadData.ids = $('.entries li').map(() ->
      $(@).data('entry-id')
    ).get().join()
    $.post feedbin.data.mark_as_read_path, feedbin.markReadData

  checkPushPermission: (permissionData) ->
    if (permissionData.permission == 'default')
      $('body').removeClass('push-on')
      $('body').removeClass('push-disabled')
      $('body').addClass('push-off')
    else if (permissionData.permission == 'granted')
      $('body').removeClass('push-off')
      $('body').removeClass('push-disabled')
      $('body').addClass('push-on')
    else if (permissionData.permission == 'denied')
      $('body').removeClass('push-on')
      $('body').removeClass('push-off')
      $('body').addClass('push-disabled')

  toggleFullScreen: ->
    $('body').toggleClass('full-screen')
    feedbin.measureEntryColumn()

  isFullScreen: ->
    $('body').hasClass('full-screen')

  nextEntry: ->
    nextEntry = $('.entries').find('.selected').next()
    if nextEntry.length
      nextEntry
    else
      null

  nextEntryPreview: () ->
    next = feedbin.selectedEntry.container.parents('li').next()
    if next.length
      title = next.find('.title').text()
      feed = next.find('.feed-title').text()
      $('.next-entry-title').text(title)
      $('.next-entry-feed').text(feed)
      $('[data-behavior~=needs_next]').prop('disabled', false)
      $('[data-behavior~=needs_next]').removeClass('no-content')
    else
      $('[data-behavior~=needs_next]').addClass('no-content')
      $('[data-behavior~=needs_next]').prop('disabled', true)

    previous = feedbin.selectedEntry.container.parents('li').prev()
    if previous.length
      $('[data-behavior~=needs_previous]').prop('disabled', false)
      $('[data-behavior~=needs_previous]').removeClass('no-content')
    else
      $('[data-behavior~=needs_previous]').addClass('no-content')
      $('[data-behavior~=needs_previous]').prop('disabled', true)



  hideSubscribe: ->
    $('.feeds-inner').removeClass('show-subscribe')
    $('.subscribe-wrap').removeClass('open')

  getSelectedText: ->
    text = ""
    if (window.getSelection)
      text = window.getSelection().toString();
    else if (document.selection && document.selection.type != "Control")
      text = document.selection.createRange().text;
    text

  scrollTo: (item, container) ->
    item.offset().top - container.offset().top + container.scrollTop()

  sortByLastUpdated: (a, b) ->
    aTimestamp = $(a).data('sort-last-updated') * 1
    bTimestamp = $(b).data('sort-last-updated') * 1
    return bTimestamp - aTimestamp

  sortByVolume: (a, b) ->
    aVolume = $(a).data('sort-post-volume') * 1
    bVolume = $(b).data('sort-post-volume') * 1
    return bVolume - aVolume

  sortByName: (a, b) ->
    $(a).data('sort-name').localeCompare($(b).data('sort-name'))

  sortByTags: (a, b) ->
    a = $(a).data('sort-tags')
    b = $(b).data('sort-tags')

    if (a == "")
      return 1
    if (b == "")
      return -1
    if (a == b)
      return 0

    a.localeCompare(b)

  sortByFeedOrder: (a, b) ->
    a = parseInt($(a).data('sort-id'))
    b = parseInt($(b).data('sort-id'))

    a = feedbin.data.feed_order.indexOf(a)
    b = feedbin.data.feed_order.indexOf(b)

    a - b

  showSearchControls: (sort) ->
    $('.search-control').removeClass('hide');
    text = null
    if sort
      text = $("[data-sort-option=#{sort}]").text()
    if !text
      text = $("[data-sort-option=desc]").text()
    $('.sort-order').text(text)
    $('.entries').addClass('show-search-options')

  hideSearchControls: ->
    $('.search-control').addClass('hide');
    $('.entries').removeClass('show-search-options')
    $('.entries').removeClass('show-saved-search')
    $('.saved-search-wrap').removeClass('open')

  buildPoints: (percentages, width, height) ->
    barWidth = width / (percentages.length - 1)
    x = 0

    points = []
    for percentage in percentages
      y = (height - Math.round(percentage * height))
      points.push({x: x, y: y})
      x += barWidth

    points

  drawBarChart: (canvas, values) ->
    if values && canvas.getContext
      lineTo = (x, y, context, height) ->
        if y == 0
          y = 1
        if y == height
          y = height - 1
        context.lineTo(x, y)

      context = canvas.getContext("2d")
      canvasHeight = $(canvas).outerHeight()
      canvasWidth = $(canvas).outerWidth()

      ratio = 1
      if 'devicePixelRatio' of window
        ratio = window.devicePixelRatio

      $(canvas).attr('width', canvasWidth * ratio)
      $(canvas).attr('height', canvasHeight * ratio)
      context.scale(ratio, ratio)

      context.lineJoin = 'round'
      context.strokeStyle = $(canvas).data('stroke')
      context.lineWidth = 1
      context.lineCap = 'round'

      points = feedbin.buildPoints(values, canvasWidth, canvasHeight)

      context.beginPath()
      for point, index in points
        if index == 0
          lineTo(point.x + 1, point.y, context, canvasHeight)
        else if index == points.length - 1
          lineTo(canvasWidth - 1, point.y, context, canvasHeight)
        else
          lineTo(point.x, point.y, context, canvasHeight)
      context.stroke()

  readabilityActive: ->
    $('[data-behavior~=toggle_content_view]').find('.active').length > 0

  prepareShareForm: ->
    $('.field-cluster input, .field-cluster textarea').val('')
    $('.share-controls [type="checkbox"]').attr('checked', false);

    title = $('.entry-header h1').first().text()
    $('.share-form .title-placeholder').val(title)

    url = $('.entry-header a').first().attr('href')
    $('.share-form .url-placeholder').val(url)

    description = feedbin.getSelectedText()
    url = $('#source_link').attr('href')
    $('.share-form .description-placeholder').val("#{description} #{url}")

    source = $('.entry-header .author').first().text()
    if source == ""
      source = $('.entry-header .feed-title').first().text()
    $('.share-form .source-placeholder').val(source)

    if feedbin.readabilityActive()
      $('.readability-placeholder').val('on')
    else
      $('.readability-placeholder').val('off')


  sharePopup: (url) ->
    windowOptions = 'scrollbars=yes,resizable=yes,toolbar=no,location=yes'
    width = 620
    height = 590
    winHeight = screen.height
    winWidth = screen.width
    left = Math.round((winWidth / 2) - (width / 2));
    top = 0;
    if (winHeight > height)
      top = Math.round((winHeight / 2) - (height / 2))
    window.open(url, 'intent', "#{windowOptions},width=#{width},height=#{height},left=#{left},top=#{top}")

  closeEntryBasement: (timeout = 200) ->
    feedbin.closeEntryBasementTimeount = setTimeout ( ->
      $('.basement-panel').addClass('hide')
      $('.field-cluster input').blur()
      $('.entry-basement').removeClass('open')
    ), timeout

    $('.entry-basement').removeClass('foreground')
    if $('.entry-content').length > 0
      $('.entry-content')[0].style.removeProperty("top")

    clearTimeout(feedbin.openEntryBasementTimeount)

  openEntryBasement: (selectedPanel) ->
    feedbin.openEntryBasementTimeount = setTimeout ( ->
      $('.entry-basement').addClass('foreground')
      $('.field-cluster input', selectedPanel).first().select()
    ), 200

    clearTimeout(feedbin.closeEntryBasementTimeount)

    feedbin.prepareShareForm()

    $('.basement-panel').addClass('hide')
    selectedPanel.removeClass('hide')
    $('.entry-basement').addClass('open')
    newTop = selectedPanel.height()
    $('.entry-content').css
      "top": "#{newTop}px"

  applyStarred: (entryId) ->
    if feedbin.Counts.get().isStarred(entryId)
      $('[data-behavior~=selected_entry_data]').addClass('starred')

  showEntry: (entryId) ->
    entry = feedbin.entries[entryId]
    feedbin.updateEntryContent(entry.content, entry.inner_content)
    feedbin.formatEntryContent(entryId, true)

  tagFeed: (url, tag, noResponse = true) ->
    $.ajax
      type: "POST",
      url: url,
      data: { _method: "patch", feed: {tag_list: tag}, no_response: noResponse }

  hideEmptyTags: ->
    $('[data-tag-id]').each ->
      if $(@).find('ul li').length == 0
        $(@).remove()

  appendTag: (target, ui) ->
    appendTarget = target.find('ul').first()
    ui.helper.remove()
    ui.draggable.appendTo(appendTarget)
    $('> [data-behavior~=sort_feed]', appendTarget).sort(feedbin.sortByFeedOrder).remove().appendTo(appendTarget)

  draggable: ->
    $('[data-behavior~=draggable]').draggable
      containment: '.feeds'
      helper: 'clone'
      appendTo: '[data-behavior~=feeds_target]'
      delay: 300
      start: (event, ui) ->
        $('.feeds').addClass('dragging')
        feedbin.dragOwner = $(@).parents('[data-behavior~=droppable]').first()
      stop: (event, ui) ->
        $('.feeds').removeClass('dragging')

  droppable: ->
    $('[data-behavior~=droppable]:not(.ui-droppable)').droppable
      hoverClass: 'drop-hover'
      greedy: true
      drop: (event, ui) ->
        if !feedbin.dragOwner.get(0).isEqualNode(event.target)

          feedId = parseInt(ui.draggable.data('feed-id'))
          url = ui.draggable.data('feed-path')
          target = $(event.target)
          tag = $("> a", event.target).find("[data-behavior~=rename_title]").text()

          if tag?
            tagId = $(event.target).data('tag-id')
          else
            tag = ""
            tagId = null

          feedbin.Counts.get().updateTagMap(feedId, tagId)
          feedbin.tagFeed(url, tag)
          feedbin.appendTag(target, ui)
          feedbin.hideEmptyTags()
          feedbin.applyCounts(false)
          setTimeout ( ->
            feedbin.draggable()
          ), 20

  refreshRetry: (xhr) ->
    $.get(feedbin.data.refresh_sessions_path).success(->
      $.ajax(xhr)
    )

  showModal: (target, title = null) ->
    modal = $("#modal")
    classes = modal[0].className.split(/\s+/)
    classPrefix = "modal-purpose"
    modalClass = "#{classPrefix}-#{target}"

    content = $($("[data-modal-purpose=#{target}]").html())

    titleElement = content.find(".modal-title")
    title = title or titleElement.html()
    titleElement.html(title)

    $.each classes, (index, className) ->
      if className.indexOf(classPrefix) != -1
        modal.removeClass className

    modal.html(content)
    modal.addClass(modalClass)
    modal.modal('show')
    modalClass

  loadLink: (href) ->
    form = $("[data-behavior~=view_link_form]")
    $("#url", form).val(href)
    form.submit()
    $('.entry-final-content a [data-behavior~=link_actions]').remove()

  updateFeedSearchMessage: ->
    length = $('[data-behavior~=subscription_option] [data-behavior~=check_toggle]:checked').length
    show = (message) ->
      $(".modal-purpose-subscribe [data-behavior~=feeds_search_message]").addClass("hide")
      $(".modal-purpose-subscribe [data-behavior~=feeds_search_message][data-behavior~=#{message}]").removeClass("hide")

    if length == 0
      show("message_none")
    else if length == 1
      show("message_one")
    else
      show("message_multiple")

  measureEntryColumn: ->
    width = $(".entry-column").outerWidth()
    if width
      $(".entry-column").removeClass("wide")
      $(".entry-column").removeClass("narrow")
      if width > 775
        $(".entry-column").addClass("wide")
      else
        $(".entry-column").addClass("narrow")

  embeds: {}

  entries: {}

  feedCandidates: []

  images: []

  feedXhr: null

  readabilityXHR: null

  markReadData: {}

  closeSubcription: false

  player: null

  recentlyReadTimer: null

  selectedFeed: null

  dragOwner: null

  preloadedImageIds: []

  linkActionsTimer: null

  linkCacheTimer: null

  ONE_HOUR: 60 * 60 * 1000

  ONE_DAY: 60 * 60 * 1000 * 24

$.extend feedbin,
  preInit:

    xsrf: ->
      setup =
        beforeSend: (xhr) ->
          matches = document.cookie.match(/XSRF\-TOKEN\=([^;]*)/)
          if matches && matches[1]
            token = decodeURIComponent(matches[1])
            xhr.setRequestHeader('X-XSRF-TOKEN', token)
      $.ajaxSetup(setup);

  init:

    baseFontSize: ->
      element = document.createElement('div')
      content = document.createTextNode('content')
      element.appendChild content
      element.style.display = 'none'
      element.style.font = '-apple-system-body'

      if element.style.font == ""
        base = "16"
      else
        document.body.appendChild element
        style = window.getComputedStyle(element, null)
        size = style.getPropertyValue 'font-size'
        base = parseInt(size) - 1

      $("html").css
        "font-size": "#{base}px"

    faviconColors: ->
      feedbin.faviconColors($(".feeds-column"))

    hasScrollBars: ->
      if feedbin.scrollBars()
        $('body').addClass('scroll-bars')

    hasScrollSnap: ->
      if 'scroll-snap-type' of document.body.style
        feedbin.swipe = true
        $('body').addClass('swipe')

    hasTouch: ->
      if 'ontouchstart' of document
        $('body').addClass('touch')
      else
        $('body').addClass('no-touch')

    isStandalone: ->
      if 'standalone' of window.navigator && window.navigator.standalone
        $('body').addClass('standalone-navigator')

    initSingletons: ->
      new feedbin.CountsBehavior()

    state: ->
      $(window).on 'popstate', (event) ->
        if feedbin.panel > 1
          newPanel = feedbin.panel - 1
          feedbin.showPanel(newPanel, false)

    userTitles: ->
      feedbin.applyUserTitles()

    renameFeed: ->
      $(document).on 'dblclick', '[data-behavior~=renamable]', (event) ->
        unless $(event.target).is('.feed-action-button')
          target = $(@).find('[data-behavior~=rename_target]')
          title = $(@).find('[data-behavior~=rename_title]')
          data = target.data()

          formAttributes =
            "accept-charset": "UTF-8"
            "data-remote": "true"
            "method": "post"
            "action": data.formAction
            "data-behavior": "rename_form"
            "class": "rename-form"
          form = $('<form>', formAttributes)

          inputAttributes =
            "placeholder": data.originalTitle
            "value": data.title
            "name": data.inputName
            "data-behavior": "rename_input"
            "type": "text"
            "spellcheck": "false"
            "class": "rename-feed-input"

          input = $('<input>', inputAttributes)
          methodInput = $('<input>', {type: "hidden", name: "_method", value: "patch"})

          form.append(input)
          form.append(methodInput)

          title.addClass('hide')
          target.append(form)
          input.select()

      $(document).on 'blur', '[data-behavior~=rename_input]', (event) ->
        $('[data-behavior~=rename_form]').remove()
        $('[data-behavior~=rename_title]').removeClass('hide')

      $(document).on 'submit', '[data-behavior~=rename_form]', (event, xhr) ->
        container = $(@).closest('[data-behavior~=renamable]')
        title = container.find('[data-behavior~=rename_title]')
        input = container.find('[data-behavior~=rename_input]')
        target = container.find('[data-behavior~=rename_target]')
        target.data('title', input.val())
        title.text(input.val())

        $('[data-behavior~=rename_form]').remove()
        $('[data-behavior~=rename_title]').removeClass('hide')

      $(document).on 'click', '[data-behavior~=rename_input]', (event) ->
        event.stopPropagation()
        event.preventDefault()

      $(document).on 'click', '[data-behavior~=open_item]', (event) ->
        unless $(event.target).is('[data-behavior~=rename_input]')
          $('[data-behavior~=rename_input]').each ->
            $(@).blur()

    changeSearchSort: (sort) ->
      $(document).on 'click', '[data-sort-option]', ->
        sortOption = $(@).data('sort-option')
        searchField = $('#query')
        query = searchField.val()
        query = query.replace(/\s*?(sort:\s*?asc|sort:\s*?desc|sort:\s*?relevance)\s*?/, '')
        query = "#{query} sort:#{sortOption}"
        searchField.val(query)
        searchField.parents('form').submit()

    markRead: ->
      $(document).on 'click', '[data-mark-read]', ->
        feedbin.markReadData = $(@).data('mark-read')
        $('[data-behavior~=mark_all_as_read]').removeAttr('disabled')
        return

      $(document).on 'click', '[data-behavior~=mark_all_as_read]', ->
        unless $(@).attr('disabled')
          $('.entries li').map ->
            entry_id = $(@).data('entry-id') * 1

          if feedbin.data.mark_as_read_confirmation
            result = confirm(feedbin.markReadData.message)
            if result
              feedbin.markRead()
          else
            feedbin.markRead()
        return

    selectable: ->
      $(document).on 'click', '[data-behavior~=selectable]', ->
        $(@).parents('ul').find('.selected').removeClass('selected')
        $(@).parent('li').addClass('selected')
        return

    choicesSubmit: ->
      $(document).on 'ajax:beforeSend', '[data-choice-form]', ->
        $('.modal').modal('hide')
        return

    entryLinks: ->
      $(document).on 'click', '[data-behavior~=external_links] a', ->
        $(this).attr('target', '_blank').attr('rel', 'noopener noreferrer')
        return

    clearEntry: ->
      $(document).on 'ajax:beforeSend', '[data-behavior~=show_entries]', (event) ->
        unless $(event.target).is('.toggle-drawer')
          feedbin.clearEntry()
        return

    cancelFeedRequest: ->
      $(document).on 'ajax:beforeSend', '[data-behavior~=show_entries]', (event, xhr) ->
        if $(event.target).is(".toggle-drawer")
          return

        if feedbin.feedXhr
          feedbin.feedXhr.abort()
        if $(event.target).is('.edit_feed')
          feedbin.feedXhr = null
        else
          feedbin.feedXhr = xhr
        return

    tooltips: ->
      $(document).on 'mouseenter mouseleave', '[data-behavior~=tooltip]', (event) ->
        tooltip = $(this).tooltip
          delay: 0
          animation: false
        if 'mouseenter' == event.type
          tooltip.tooltip('show')
        else
          tooltip.tooltip('hide')
        return

    loadEntries: ->
      link = $('[data-behavior~=feeds_target] li:visible').first().find('a')
      mobile = $('body').hasClass('mobile')
      if link.length > 0 && !mobile
        link[0].click()

    resizeWindow: ->
      feedbin.measureEntryColumn()
      measure = _.throttle(feedbin.measureEntryColumn, 100);
      $(window).on "resize", measure

    resizeColumns: ->
      measure = _.throttle(feedbin.measureEntryColumn, 100);

      defaults =
        handles: "e"
        minWidth: 200
        resize: (event, ui) ->
          measure()
        stop: (event, ui) ->
          form = $('[data-behavior~=resizable_form]')
          $('[name=column]', form).val($(ui.element).data('resizable-name'))
          $('[name=width]', form).val(ui.size.width)
          form.submit()
          return
      $('.feeds-column').resizable($.extend(defaults))
      $('.entries-column').resizable($.extend(defaults))

    feedCandidates: ->
      $(document).on 'click', '[data-behavior~=show_entries]', ->
        clickedItem = $(@).parents 'li'
        feedbin.feedCandidates = []
        feedbin.feedCandidates.push clickedItem.next().data('feed-id') if clickedItem.next().length
        feedbin.feedCandidates.push clickedItem.prev().data('feed-id') if clickedItem.prev().length
        return

    unauthorizedResponse: ->
      $(document).on 'ajax:complete', (event, response, status) ->
        if response.status == 401
          document.location = feedbin.data.login_url
        return

    screenshotTabs: ->
      $('[data-behavior~=screenshot_nav] li').first().addClass('active')
      $(document).on 'click', '[data-behavior~=screenshot_nav] a', (event) ->
        $('[data-behavior~=screenshot_nav] li').removeClass('active')
        $(@).parent('li').addClass('active')
        src = $(@).find('img').attr('src')
        $("[data-behavior~=screenshots] img").addClass('hide')
        $("[data-behavior~=screenshots] img[src='#{src}']").removeClass('hide')
        event.preventDefault()
        return

      $(document).on 'click', '[data-behavior~=screenshot_previous], [data-behavior~=screenshot_next]', (event) ->
        selectedScreenshot = $('[data-behavior~=screenshot_nav] li.active')
        button = $(event.target).data('behavior')
        if button.match(/screenshot_next/)
          nextScreenshot = selectedScreenshot.next()
          if nextScreenshot.length == 0
            nextScreenshot = $('li:first-child', $('[data-behavior~=screenshot_nav]'))
        else
          nextScreenshot = selectedScreenshot.prev()
          if nextScreenshot.length == 0
            nextScreenshot = $('li:last-child', $('[data-behavior~=screenshot_nav]'))

        nextScreenshot.find('a').click()
        event.preventDefault()
        return

    entriesLoading: ->
      $(document).on 'click', '[data-behavior~=feed_link]', (event) ->
        $(".entries").addClass("loading")
        title = $(".collection-label-wrap", @).text()
        $("[data-behavior~=entries_header] .feed-title-wrap").text(title)
        true

      $(document).on 'ajax:complete', '[data-behavior~=feed_link]', (event, xhr) ->
        $(".entries").removeClass("loading")
        true

    feedSelected: ->
      $(document).on 'click', '[data-behavior~=show_feeds]', ->
        feedbin.showPanel(1)

      $(document).on 'click', '[data-behavior~=show_entries]', (event) ->
        feedbin.showPanel(2)

      $(document).on 'click', '[data-behavior~=show_entry_content]', ->
        feedbin.showPanel(3)

    addFields: ->
      $(document).on 'click', '[data-behavior~=add_fields]', (event) ->
        time = new Date().getTime() + '_insert'
        id = $(@).data('id')
        regexp = new RegExp(id, 'g')
        content = $(@).data('fields').replace(regexp, time)
        $('[data-behavior~=add_fields_target]').find('tbody').prepend(content)
        event.preventDefault()
        return

    removeFields: ->
      $(document).on 'click', '[data-behavior~=remove_fields]', (event) ->
        $(@).prev('input[type=hidden]').val(1)
        $(@).closest('tr').addClass('hide')
        event.preventDefault()
        return

    dropdown: ->
      $(document).on 'click', (event) ->
        dropdown = $('.dropdown-wrap')
        unless $(event.target).is('[data-behavior~=toggle_dropdown]') || $(event.target).parents('[data-behavior~=toggle_dropdown]').length > 0
          dropdown.removeClass('open')
        return

      $(document).on 'click', '[data-behavior~=share_options] a', (event) ->
        $('.dropdown-wrap').removeClass('open')

      $(document).on 'click', '[data-behavior~=toggle_dropdown]', (event) ->
        $(".dropdown-wrap li").removeClass('selected')
        parent = $(@).closest('.dropdown-wrap')
        if parent.hasClass('open')
          parent.removeClass('open')
        else
          parent.addClass('open')
        event.preventDefault()
        return

      $(document).on 'mouseover', '.dropdown-wrap li', (event) ->
        $('.dropdown-wrap li').not(@).removeClass('selected')
        return

    drawer: ->
      $(document).on 'click', '[data-behavior~=toggle_drawer]', (event) =>
        button = $(event.currentTarget)
        drawer = button.parents('li').find('.drawer')

        if drawer.data('hidden') == true
          height = $('ul', drawer).height() + 2
          hidden = false
          text = 'hide'
        else
          height = 0
          hidden = true
          text = 'show'

        drawer.animate {
          height: height
        }, 200, ->
          if height > 0
            drawer.css
              height: 'auto'

        drawer.data('hidden', hidden)
        button.text(text)

        button.parent('form').submit()
        event.stopPropagation()
        event.preventDefault()
        return

    feedActions: ->
      $(document).on 'click', '[data-operation]', (event) ->
        operation = $(@).data('operation')
        form = $(@).parents('form')
        $('input[name=operation]').val(operation)
        form.submit()

    checkBoxToggle: ->
      $(document).on 'change', '[data-behavior~=include_all]', (event) ->
        if $(@).is(':checked')
          $('[data-behavior~=toggle_checked_target] [type="checkbox"][name]').prop('disabled', true)
        else
          $('[data-behavior~=toggle_checked_target] [type="checkbox"][name]').prop('disabled', false)

      $(document).on 'change', '[data-behavior~=toggle_checked]', (event) ->

        $('[data-behavior~=toggle_checked_hidden]').toggleClass('hide')

        if $(@).is(':checked')
          $('[data-behavior~=toggle_checked_target] [type="checkbox"][name]').prop('checked', true)
        else
          $('[data-behavior~=toggle_checked_target] [type="checkbox"][name]').prop('checked', false)
        event.preventDefault()
        return

      $(document).on 'click', '[data-behavior~=check_feeds]', (event) ->
        checkboxes = $('[data-behavior~=collection_checkbox]')
        if $(@).is(':checked')
          checkboxes.prop('checked', true)
          checkboxes.attr('disabled', 'disabled')
        else
          checkboxes.prop('checked', false)
          checkboxes.removeAttr('disabled')
        return

    validateFile: ->
      form = $('.new_import_uploader')
      input = form.find("input:file")
      unless input.val()
        form.find('[type=submit]').attr('disabled','disabled')

      input.on 'change', ()->
        if $(this).val()
          form.find('[type=submit]').removeAttr('disabled')
        return

    timeago: ->
      strings =
        prefixAgo: null
        prefixFromNow: null
        suffixAgo: ""
        suffixFromNow: "from now"
        seconds: "less than 1 min"
        minute: "1m"
        minutes: "%dm"
        hour: "1h"
        hours: "%dh"
        day: "1d"
        days: "%dd"
        month: "a month"
        months: "%d months"
        year: "a year"
        years: "%d years"
        wordSeparator: " "
        numbers: []
      jQuery.timeago.settings.strings = strings
      jQuery.timeago.settings.allowFuture = true
      $("time.timeago").timeago()
      return

    updateReadability: ->
      $(document).on 'ajax:complete', '[data-behavior~=toggle_content_view]', (event, xhr) ->
        feedbin.readabilityXHR = null;
        $('.button-toggle-content').removeClass('loading')

      $(document).on 'ajax:beforeSend', '[data-behavior~=toggle_content_view]', (event, xhr) ->
        if feedbin.readabilityXHR
          feedbin.readabilityXHR.abort()
          xhr.abort()

          feedbin.readabilityXHR = null
          $('.button-toggle-content').removeClass('loading')

          if feedbin.previousContent
            $('[data-behavior~=entry_content_wrap]').html(feedbin.previousContent)
            feedbin.previousContent = null
        else
          $('.button-toggle-content').addClass('loading')
          feedbin.readabilityXHR = xhr

        if feedbin.automaticSubmit != true
          $.post($(@).data("sticky-url"))

        feedbin.automaticSubmit = false

        true

    autoUpdate: ->
      setInterval ( ->
        feedbin.refresh()
      ), 300000

    entryBasement: ->

      $(document).on 'click', (event, xhr) ->
        if ($(event.target).hasClass('entry-basement') || $(event.target).parents('.entry-basement').length > 0)
          false

        isButton = (event) ->
          $(event.target).is('[data-behavior~=show_entry_basement]') ||
          $(event.target).parents('[data-behavior~=show_entry_basement]').length > 0

        if !isButton(event) && $(event.target).parents('.entry-basement').length == 0
          feedbin.closeEntryBasement()
        return

      $(document).on 'click', '[data-behavior~=show_entry_basement]', (event, xhr) ->
        panelName = $(@).data('basement-panel')
        selectedPanel = $("[data-basement-panel-target=#{panelName}]")

        if $('.entry-basement').hasClass('open')
          if selectedPanel.hasClass('hide')
            # There is another panel open, transition to the clicked on panel
            feedbin.closeEntryBasement()
            feedbin.openEntryBasement(selectedPanel)
          else
            # The clicked on panel is alread open, close it
            feedbin.closeEntryBasement()
        else
          feedbin.openEntryBasement(selectedPanel)

        event.preventDefault()
        return

      $(document).on 'click', '[data-behavior~=close_entry_basement]', (event, xhr) ->
        feedbin.closeEntryBasement()
        event.preventDefault()
        return

      $(document).on 'submit', '.share-form form', (event, xhr) ->
        feedbin.closeEntryBasement()
        return

    supportedSharing: ->
      $(document).on 'click', '.button-toggle-share-menu [data-behavior~=show_entry_basement]', (event, xhr) ->
        panelName = $(@).data('basement-panel')
        selectedPanel = $("[data-basement-panel-target=#{panelName}]")
        $('form', selectedPanel).attr('action', $(@).attr('href'))

    formatToolbar: ->
      selectedFont = $("[data-font]").data('font')
      feedbin.fonts(selectedFont)
      $('[data-behavior~=change_font]').val(selectedFont)
      $('[data-behavior~=change_font]').change ->
        fontContainer = $("[data-font]")
        currentFont = fontContainer.data('font')
        newFont = $(@).val()
        fontContainer.removeClass("font-#{currentFont}")
        fontContainer.addClass("font-#{newFont}")
        fontContainer.data('font', newFont)
        $(@).parents('form').submit()
        feedbin.fonts(newFont)

    feedSettings: ->
      $(document).on 'click', '[data-behavior~=sort_feeds]', (event, xhr) ->
        sortBy = $(@).data('value')
        label = $(@).text()
        $('[data-behavior~=sort_label]').text(label)
        if sortBy == "name"
          sortFunction = feedbin.sortByName
        else if sortBy == "last-updated"
          sortFunction = feedbin.sortByLastUpdated
        else if sortBy == "volume"
          sortFunction = feedbin.sortByVolume
        else if sortBy == "tags"
          sortFunction = feedbin.sortByTags
        $('.sortable li').sort(sortFunction).appendTo('.sortable');
      return

    fontSize: ->
      $(document).on 'click', '[data-behavior~=increase_font]', (event) ->
        feedbin.updateFontSize('increase')
        return

      $(document).on 'click', '[data-behavior~=decrease_font]', (event) ->
        feedbin.updateFontSize('decrease')
        return

    entryWidth: ->
      $(document).on 'click', '[data-behavior~=entry_width]', (event) ->
        $('[data-behavior~=entry_content_target]').toggleClass('fluid')
        $('body').toggleClass('fluid')
        return

    fullscreen: ->
      $(document).on 'click', '[data-behavior~=full_screen]', (event) ->
        feedbin.toggleFullScreen()
        feedbin.closeEntryBasement()
        event.preventDefault()
        return

    showSearch: ->
      $(document).on 'click', '[data-behavior~=show_search]', (event) ->
        $('body').toggleClass('hide-search')
        event.preventDefault()
        return

    titleBarColor: ->
      if feedbin.native && feedbin.data.theme
        rgb = $("[data-theme=#{feedbin.data.theme}]").css("backgroundColor")
        feedbin.setNativeTitleColor(rgb)

      $(document).on 'click', '[data-behavior~=switch_theme]', (event) ->
        feedbin.data.theme = $(@).data('theme')
        if feedbin.native
          rgb = $("[data-theme=#{feedbin.data.theme}]").css("backgroundColor")
          feedbin.setNativeTitleColor(rgb)

    theme: ->
      $(document).on 'click', '[data-behavior~=switch_theme]', (event) ->
        theme = $(@).data('theme')
        $('[data-behavior~=class_target]').removeClass('theme-day')
        $('[data-behavior~=class_target]').removeClass('theme-sunset')
        $('[data-behavior~=class_target]').removeClass('theme-night')
        $('[data-behavior~=class_target]').addClass("theme-#{theme}")
        event.preventDefault()

        return

    showEntryActions: ->
      $(document).on 'click', '[data-behavior~=show_entry_actions]', (event) ->
        parent = $(@).parents('li')
        if parent.hasClass('show-actions')
          $('.entries li').removeClass('show-actions')
        else
          $('.entries li').removeClass('show-actions')
          parent.addClass('show-actions')
        event.preventDefault()
        event.stopPropagation()
        return

      $(document).on 'click', (event) ->
        $('.entries li').removeClass('show-actions')
        return

      $(document).on 'click', '[data-behavior~=show_entry_content]', (event) ->
        unless $(event.target).is('[data-behavior~=show_entry_actions]')
          $('.entries li').removeClass('show-actions')
        return

    markDirectionAsRead: ->
      $(document).on 'click', '[data-behavior~=mark_below_read], [data-behavior~=mark_above_read]', (event) ->
        data = feedbin.markReadData
        if data
          data['ids'] = $(@).parents('li').prevAll().map(() ->
            $(@).data('entry-id')
          ).get().join()

          if $(@).is('[data-behavior~=mark_below_read]')
            $(@).parents('li').nextAll().addClass('read')
            data['direction'] = 'below'
          else
            $(@).parents('li').prevAll().addClass('read')
            data['direction'] = 'above'

        $.post feedbin.data.mark_direction_as_read_entries, data
        return

    hideUpdates: ->
      $(document).on 'click', '[data-behavior~=hide_updates]', (event) ->
        container = $(@).parents('.diff-wrap')
        if feedbin.data.update_message_seen
          container.addClass('hide')
        else
          feedbin.data.update_message_seen = true
          container.find('.diff-wrap-text').text('To re-enable updates, go to Setting > Feeds.')
          setTimeout ( ->
            container.addClass('hide')
          ), 4000

    toggle: ->
      $(document).on 'click', '[data-toggle]', ->
        toggle = $(@).data('toggle')
        if toggle['class']
          $(@).toggleClass(toggle['class'])
        if toggle['title']
          if toggle['title'][0] == $(@).attr('title')
            title = toggle['title'][1]
          else
            title = toggle['title'][0]
          $(@).attr('title', title)

    feedsSearch: ->
      $(document).on 'submit', '[data-behavior~=feeds_search]', ->
        $('.modal-purpose-subscribe .feed-search-results').hide()
        $('[data-behavior~=feeds_search_favicon_target]').html('')
        $('.modal-purpose-subscribe .modal-dialog').removeClass('done');

    formProcessing: ->
      $(document).on 'submit', '[data-behavior~=spinner], [data-behavior~=subscription_form], [data-behavior~=search_form], [data-behavior~=feeds_search]', ->
        $(@).find('input').addClass('processing')
        return

      $(document).on 'ajax:complete', '[data-behavior~=spinner], [data-behavior~=subscription_form], [data-behavior~=search_form], [data-behavior~=feeds_search]', ->
        $(@).find('input').removeClass('processing')
        if feedbin.closeSubcription
          setTimeout ( ->
            feedbin.hideSubscribe()
          ), 600
          feedbin.closeSubcription = false
        return

    searchError: ->
      $(document).on 'ajax:error', '[data-behavior~=search_form]', (event, xhr) ->
        feedbin.showNotification('Search error.', 3000, '', true);

        return

    savedSearch: ->
      $(document).on 'click', '[data-behavior~=save_search_link]', ->
        query = $('#query').val()
        $('#saved_search_query').val(query)
        $('.entries').toggleClass('show-saved-search')
        $('.saved-search-wrap').toggleClass('open')
        $('#saved_search_name').focus()
        return

      $(document).on 'click', '[data-behavior~=feed_link]:not(.saved-search-link)', ->
        $('#query').val('')

    showPushOptions: ->
      if "safari" of window and "pushNotification" of window.safari
        $('body').addClass('supports-push')
        if $('#push-data').length > 0
          $('.push-options').removeClass('hide')
          data = $('#push-data').data()
          permissionData = window.safari.pushNotification.permission(data.websiteId)
          feedbin.checkPushPermission(permissionData )

    enablePush: ->
      $(document).on 'click', '[data-behavior~=enable_push]', (event) ->
        data = $('#push-data').data()
        window.safari.pushNotification.requestPermission(data.webServiceUrl, data.websiteId, {authentication_token: data.authenticationToken}, feedbin.checkPushPermission)
        event.preventDefault()
        return

    deleteAssociatedRecord: ->
      $(document).on 'click', '.remove_fields', (event) ->
        $(@).parents('[data-behavior~=associated_record]').hide(200)

    editAction: ->
      $(document).on 'click', '[data-behavior~=edit_action]', (event) ->
        actionForm = $(@).parents('.action-form')
        editForm = actionForm.find('.action-edit-form')
        actionDescription = $(@).parents('.action-form').find('.action-description')
        if editForm.hasClass('hide')
          editForm.removeClass('hide')
          actionForm.addClass('selected')
          actionDescription.addClass('hide')
        else
          editForm.addClass('hide')
          actionForm.removeClass('selected')
          actionDescription.removeClass('hide')
        event.stopPropagation()
        event.preventDefault()
        return

    loadViewChanges: ->
      $(document).on 'ajax:beforeSend', '[data-behavior~=load_view_changes]', (event, xhr) ->
        if $('[data-behavior~=diff_content]').length
          xhr.abort()
          feedbin.toggleDiff()

    viewLatest: ->
      $(document).on 'click', '.view-latest-link', ->
        feedbin.toggleDiff()

    serviceOptions: ->
      $(document).on 'click', '[data-behavior~=show_service_options]', (event) ->
        height = $(@).parents('li').find('.service-options').outerHeight()
        $(@).parents('li').find('.service-options-wrap').addClass('open').css
          height: height
        $(@).parents('li').find('.show-service-options').addClass('hide')
        event.preventDefault()
        return

      $(document).on 'click', '[data-behavior~=hide_service_options]', (event) ->
        $(@).parents('li').find('.service-options-wrap').removeClass('open').css
          height: 0
        $(@).parents('li').find('.show-service-options').removeClass('hide')
        event.preventDefault()
        return

    drawBarCharts: ->
      feedbin.drawBarCharts()

    selectText: ->
      $(document).on 'mouseup', '[data-behavior~=select_text]', (event) ->
        $(@).select()
        event.preventDefault()
      return

    fuzzyFilter: ->
      feeds = $('[data-sort-name]')
      $(document).on 'keyup', '[data-behavior~=feed_search]', ->
        suggestions = []
        query = $(@).val()
        if query.length < 1
          suggestions = feeds
        else
          $.each feeds, (i, feed) ->
            sortName = $(feed).data('sort-name')
            if feed && sortName && query && typeof(query) == "string" && typeof(sortName) == "string"
              feed.score = sortName.score(query)
            else
              feed.score = 0
            if feed.score > 0
              suggestions.push(feed);
          if suggestions.length > 0
            suggestions = _.sortBy suggestions, (suggestion) ->
              -(suggestion.score)
          else
            suggestions = ''
        $('[data-behavior~=search_results]').html(suggestions)
      return

    appearanceRadio: ->
      $('[data-behavior~=appearance_radio]').on 'change', (event) ->
        selected = $(@).val()
        setting = $(@).data('setting')
        name = $(@).attr('name')

        $("[name='#{name}']").each ->
          option = $(@).val()
          $('[data-behavior~=class_target]').removeClass("#{setting}-#{option}")

        $('[data-behavior~=class_target]').addClass("#{setting}-#{selected}")

    appearanceCheckbox: ->
      $(document).on 'click', '[data-behavior~=appearance_checkbox]', (event) ->
        checked = if $(@).is(':checked') then '1' else '0'
        setting = $(@).data('setting')
        $('[data-behavior~=class_target]').removeClass("#{setting}-1")
        $('[data-behavior~=class_target]').removeClass("#{setting}-0")
        $('[data-behavior~=class_target]').addClass("#{setting}-#{checked}")

    generalAutocomplete: ->
      $(document).on 'focus', '[data-behavior~=autocomplete_field]', (event) ->
        field = $(event.currentTarget)
        field.autocomplete
          serviceUrl: field.data('autocompletePath')
          appendTo: field.parent("[data-behavior~=autocomplete_parent]").find("[data-behavior=autocomplete_target]")
          delimiter: /(,)\s*/
          deferRequestBy: 50
          autoSelectFirst: true

    entriesMaxWidth: ->
      container = $('[data-behavior~=entries_max_width]')
      resize = ->
        windowWidth = $(window).width()
        if windowWidth < 528
          width = windowWidth - 100
        else if windowWidth < 1083
          width = windowWidth - 350
        $('.settings .entries-display-inline .entries').css({"max-width": "#{width}px"})
      if container
        throttledResize = _.throttle(resize, 50)
        $(window).on('resize', throttledResize);
        resize()


    tumblrType: ->
      $(document).on 'change', '[data-behavior~=tumblr_type]', ->
        type = $(@).val()
        description = $(@).find("option:selected").data('description-name')
        typeText = $(@).find("option:selected").text()
        if type == 'quote'
          $('.share-form .source-placeholder').removeClass('hide')
          $('.share-form .title-placeholder').addClass('hide')
        else
          $('.share-form .source-placeholder').addClass('hide')
          $('.share-form .title-placeholder').removeClass('hide')

        $('.share-form .type-text').text(typeText)
        $('.share-form .description-placeholder').attr('placeholder', description)

    dragAndDrop: ->
      feedbin.droppable()
      feedbin.draggable()

    selectCategory: ->
      $(document).on 'click', '[data-behavior~=selected_category]', (event) ->
        $(@).find('[data-behavior~=categories]').toggleClass('hide')

    resizeGraph: ->
      if $("[data-behavior~=resize_graph]").length
        $(window).resize(_.debounce(->
          $('[data-behavior~=resize_graph]').each ()->
            feedbin.drawBarChart(@, $(@).data('values'))
        20))

    settingsCheckbox: ->
      $(document).on 'change', '[data-behavior~=auto_submit]', (event) ->
        $(@).parents("form").submit()

    submitAdd: ->
      $(document).on 'submit', '[data-behavior~=subscription_options]', (event) ->
        $('[data-behavior~=submit_add]').attr('disabled', 'disabled')

      $(document).on 'click', '[data-behavior~=submit_add]', (event) ->
        $("[data-behavior~=subscription_options]").submit()

    toggleContent: ->
      $(document).on 'click', '[data-behavior~=toggle_content_button]', (event) ->
        $(@).parents("form").submit()

    checkToggle: ->
      $(document).on 'change', '[data-behavior~=subscription_option] [data-behavior~=check_toggle]', (event) ->
        length = $('[data-behavior~=subscription_option] [data-behavior~=check_toggle]:checked').length
        if length == 0
          $('.modal-purpose-subscribe [data-behavior~=submit_add]').attr('disabled', 'disabled')
        else
          $('.modal-purpose-subscribe [data-behavior~=submit_add]').removeAttr('disabled', 'disabled')
        feedbin.updateFeedSearchMessage()

    linkActionsHover: ->
      $(document).on 'mouseenter mouseleave', 'body:not(.touch) .entry-final-content a', (event) ->
        link = $(@)
        if link.text().trim().length > 0 && !$(@).has('.mejs__container').length > 0 && !link.closest(".system-content").length
          clearTimeout(feedbin.linkActionsTimer)
          clearTimeout(feedbin.linkCacheTimer)
          $('.entry-final-content a [data-behavior~=link_actions]').remove()

          contents = $('[data-behavior~=link_actions]').clone()
          contents = contents[0].outerHTML

          if event.type == "mouseenter"
            feedbin.linkCacheTimer = setTimeout ( ->
              form = $("[data-behavior~=view_link_cache_form]")
              $("#url", form).val(link.attr('href'))
              form.submit()
            ), 100
            feedbin.linkActionsTimer = setTimeout ( ->
              link.append(contents)
            ), 400

    loadLinksInApp: ->
      $(document).on 'click', '[data-behavior~=entry_final_content] a', (event) ->
        newTab = (event.ctrlKey || event.metaKey)
        linkActions = $(event.target).is(".link-actions")
        if feedbin.data.view_links_in_app && !linkActions && !newTab
          href = $(@).attr('href')
          feedbin.loadLink(href)
          event.preventDefault()

    openModal: ->
      $(document).on 'click', '[data-behavior~=open_modal]', (event) ->
        target = $(@).data("modal-target")
        title = $(@).data("modal-title")
        feedbin.showModal(target, title)

    showMessage: ->
      $(document).on 'click', '[data-behavior~=show_message]', (event) ->
        message = $(@).data("message")
        if message
          feedbin.showNotification(message)
        event.preventDefault()

    autoSubmit: ->
      throttled = _.throttle((item)->
        item.closest('form').submit();
      800);

      $(document).on 'input', '[data-behavior~=autosubmit]', (event) ->
        throttled($(@))

    loadIframe: ->
      $(document).on 'click', '[data-behavior~=iframe_placeholder]', (event) ->

        iframe = $("<iframe>").attr
          "src": $(@).data("iframe-src")
          "width": $(@).data("iframe-width")
          "height": $(@).data("iframe-height")
          "allowfullscreen": true
          "frameborder": 0

        target = $("[data-behavior~=iframe_target]", @)
        if target.length == 0
          $(@).html iframe
          feedbin.fitVids($(@))
        else
          target.html iframe

        $(@).closest(".iframe-embed").addClass("loaded")

    modalShowHide: ->
      $(document).on 'show.bs.modal', () ->
        if feedbin.data && feedbin.data.theme && background = $("[data-theme=#{feedbin.data.theme}]").css("backgroundColor")
          color = feedbin.calculateColor(background, "rgba(0, 0, 0, 0.5)")
          feedbin.setNativeTitleColor(color)

      $(document).on 'shown.bs.modal', () ->
        setTimeout ( ->
          $("body").addClass("modal-shown")
        ), 150

      $(document).on 'hidden.bs.modal', () ->
        $("body").removeClass("modal-shown")
        if feedbin.data && feedbin.data.theme
          rgb = $("[data-theme=#{feedbin.data.theme}]").css("backgroundColor")
          feedbin.setNativeTitleColor(rgb)

    scrollLeft: ->
      entries = $('.entries-column')
      article = $('.entry-column')
      $('.app-wrap').on 'scroll', (event) ->
        position = $(@).prop("scrollLeft")

        entriesPosition = entries.prop("offsetLeft")
        articlePosition = article.prop("offsetLeft")

        if position == 0
          feedbin.panel = 1
        else if position > entriesPosition - 2 && position < entriesPosition + 2
          feedbin.panel = 2
        else if position > articlePosition - 2 && position < articlePosition + 2
          feedbin.panel = 3

    statsBarTouched: ->
      $(document).on 'feedbin:native:statusbartouched', (event) ->
        feedbin.scrollToTop()

    linkActions: ->
      $(document).on 'click', '[data-behavior~=view_link]', (event) ->
        href = $(@).parents("a:first").attr('href')
        if feedbin.data.view_links_in_app
          window.open(href, '_blank');
        else
          feedbin.loadLink(href)
        event.preventDefault()

      $(document).on 'click', '[data-behavior~=link_actions]', (event) ->
        windowWidth = $(window).width()
        offset = $(@).offset().left
        width = $(".dropdown-content", @).outerWidth()

        if offset + width >= windowWidth
          $(@).addClass('open dropdown-right')
        else
          $(@).addClass('open dropdown-left')


        event.preventDefault()

    tagEditor: ->
      fieldContent = """
      <li data-behavior="remove_target" class="with-button">
        <input placeholder="Tag" type="text" name="tag_name[]">
        <button class="icon-delete" data-behavior="remove_element" type="button">Delete</button>
      </li>
      """

      $(document).on 'click', '[data-behavior~=add_tag]', (event) ->
        field = $(fieldContent)
        $("[data-behavior~=tags_target]").prepend(field)
        field.find("input").focus()
        event.preventDefault()

      $(document).on 'click', '[data-behavior~=remove_element]', (event) ->
        target = $(@).closest("[data-behavior~=remove_target]")
        target.hide 'fast', ->
          target.remove()
        event.preventDefault()

      $(document).on 'submit', '[data-behavior~=edit_tags_form]', (event) ->
        $('.modal-purpose-tags [data-behavior~=submit_tags]').attr('disabled', 'disabled')

      $(document).on 'click', '[data-behavior~=submit_tags]', (event) ->
        $('[data-behavior~=edit_tags_form]').submit()


    subscribe: ->
      $(document).on 'shown.bs.modal', (event) ->
        className = "modal-purpose-subscribe"
        if $(event.target).hasClass(className)
          $(".#{className} [data-behavior~=feeds_search_field]").focus()

      $(document).on 'hide.bs.modal', (event) ->
        $('input').blur()

      subscription = feedbin.queryString('subscribe')
      if subscription?
        $('[data-behavior~=show_subscribe]').click()
        field = $('.modal-purpose-subscribe [data-behavior~=feeds_search_field]')
        field.val(subscription)
        field.closest("form").submit()

$.each feedbin.preInit, (i, item) ->
  item()

jQuery ->
  $.each feedbin.init, (i, item) ->
    item()
