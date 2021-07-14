window.feedbin ?= {}
window.feedbin.data ?= {}

(($) ->

  $.fn.isAfter = (sel) ->
    @prevAll().filter(sel).length != 0

  $.fn.isBefore = (sel) ->
    @nextAll().filter(sel).length != 0

  return
) jQuery

$.extend feedbin,

  swipe: false
  notificationTimeout: null
  panel: 1
  panelScrollComplete: true
  jumpResultTemplate: null
  extractCache: {}
  previousContentView: 'default'
  formatMenu: null
  hasShadowDOM: typeof(document.createElement("div").attachShadow) == "function"
  colorHash: new ColorHash
  scrollStarted: false
  loadingMore: false

  prepareShareMenu: (data) ->
    buildLink = (item, data, index) ->
      href = item.url
        .replace('${url}',        encodeURIComponent(data.url))
        .replace('${title}',      encodeURIComponent(data.title))
        .replace('${source}',     encodeURIComponent(data.feed_title))
        .replace('${id}',         data.id)
        .replace('${raw_url}',    data.url)
        .replace('${twitter_id}', data.twitter_id)
        .replace('9999999999',    data.id)

      li       = $('<li>').addClass('share-option')
      label    = $('<div>').addClass('label').text(item.label)
      keyboard = $('<i>').addClass('share-keyboard').text(index)
      link     = $('<a>').attr('href', href)

      if "html_options" of item
        link.attr(item.html_options)

      link.attr('data-keyboard-shortcut', index)
      link.append(label)
      if index < 10
        link.append(keyboard)
      li.append(link)

    services = [].concat(feedbin.data.sharing)
    offset = 1
    if "share" of navigator
      if services.length > 0
        offset = 0
        services.unshift({url: '#', label: "Share using…", html_options: {"data-behavior": "navigator_share"}})
      else
        $('[data-behavior~=toggle_share_menu]').attr("data-behavior", "navigator_share toggle_share_menu")
    else if services.length == 0
      services.unshift({url: feedbin.data.sharing_path, label: "Configure…"})

    if services.length > 0
      markup = services.map (service, index) ->
        buildLink(service, data, index + offset)
      $('[data-behavior~=share_options]').html(markup)

  hideLinkAction: (url) ->
    if url of feedbin.linkActions
      tooltip = feedbin.linkActions[url].tooltip
      if url of feedbin.linkActions && !tooltip.is(':hover') && !$(feedbin.linkActions[url].popper.reference).is(':hover')
        tooltip.addClass('hide')
        tooltip.removeClass('open')
        tooltip.remove()
        feedbin.linkActions[url].popper.destroy() if feedbin.linkActions[url].popper
        delete feedbin.linkActions[url]

  hideLinkActions: ->
    for url, _ of feedbin.linkActions
      feedbin.hideLinkAction(url)

  changeContentView: (view) ->
    currentView = $('[data-behavior~=content_option]:not(.hide)')
    nextView = $("[data-behavior~=content_option][data-content-option=#{view}]")

    if view == 'extract'
      $('body').addClass('extract-active')
    else
      $('body').removeClass('extract-active')

    if !currentView.is(nextView) && nextView.length > 0
      feedbin.previousContentView = currentView.data('content-option')
      currentView.addClass('hide')
      nextView.removeClass('hide')

  loadMore: () ->
    if feedbin.scrollStarted == false
      element = $('.entries')[0]
      url = $('.pagination .next_page').attr('href')
      if url && element.scrollHeight <= element.offsetHeight
        feedbin.loadingMore = true
        $.getScript url, =>
          feedbin.loadingMore = false

  newsletterLoad: (context) ->
    feedbin.formatImages(context)
    context.querySelectorAll('a').forEach (element) ->
      element.setAttribute('target', '_blank')
      element.setAttribute('rel', 'noopener noreferrer')

  reveal: (element, callback = null) ->
    hideFeed = false
    hideTag = false
    parent = element.closest('li')
    if parent.is('.zero-count')
      feedbin.data.viewMode = 'view_all'
      parent.removeClass('zero-count')
      hideFeed = true

    unless element.is('.tag-link')
      tagParent = element.closest('[data-tag-id]')
      if !tagParent.hasClass('open')
        tagParent.find('[data-behavior~=toggle_drawer]').submit();
      if tagParent.is('.zero-count')
        tagParent.removeClass('zero-count')
        hideTag = true

    element.click()
    feedbin.hideQueue.push(tagParent.data('feed-id')) if hideTag
    feedbin.hideQueue.push(parent.data('feed-id')) if hideFeed

    setTimeout ( ->
      feedbin.scrollTo(element, $('.feeds'))
      callback() if typeof(callback) == 'function'
    ), 250

  jumpOpen: ->
    ($(".modal.modal-purpose-search").data('bs.modal') || {})._isShown

  isRelated: (selector, element) ->
    !!($(element).is(selector) || $(element).closest(selector).length)

  showSearch: (val = '') ->
    $('body').addClass('search')
    $('body').removeClass('hide-search')
    field = $('[data-behavior~=search_form] input[type=search]')
    field.focus()
    field.val(val)

  hideSearch: ->
    $('body').removeClass('search')
    $('body').removeClass('show-search-options')
    $('body').addClass('hide-search')
    field = $('[data-behavior~=search_form] input[type=search]')
    field.blur()

  toggleSearch: ->
    if $('body').hasClass('search')
      feedbin.hideSearch()
    else
      feedbin.showSearch()

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
    $("time.timeago").each ->
      element = $(@)
      element.timeago()
      element.removeClass('hide')

  panelCount: ->
    body = $('body')

    setPanels = (count) ->
      body.removeClass("one-up")
      body.removeClass("two-up")
      body.removeClass("three-up")
      body.removeClass("has-offscreen-panels")

      body.addClass("#{count}-up")
      $(document).trigger("feedbin:panels:#{count}");

    if $('body').hasClass('app')

      largeBreakpoint = 1100
      smallBreakpoint = 700
      width = $(window).width()

      if !body.hasClass("three-panels") && width > largeBreakpoint
        setPanels('three')

      if !body.hasClass("two-panels") && width <= largeBreakpoint && width > smallBreakpoint
        setPanels('two')
        body.addClass("has-offscreen-panels")

      if !body.hasClass("one-panel") && width <= smallBreakpoint
        setPanels('one')
        body.addClass("has-offscreen-panels")

  setNativeBorders: (zIndex = "front") ->
    hasBorder = (element) ->
      element.css("border-right-style") == "solid"

    borderPostion = (element) ->
      element.offset().left + element.outerWidth() - 1

    message =
      action: "borderLayout"
      borders: []
      zIndex: zIndex

    columns = ["feeds-column", "entries-column", "sidebar-column"]
    for column in columns
      element = $(".#{column}")
      if hasBorder(element)
        postion = borderPostion(element)
        if postion > 0
          message.borders.push(postion)

    feedbin.nativeMessage("performAction", message)

  tagVisibility: (values = null) ->
    if values
      localStorage.setItem(feedbin.data.visibility_key, JSON.stringify(values))
      values
    else
      JSON.parse(localStorage.getItem(feedbin.data.visibility_key)) || {}

  setTagVisibility: ->
    visibility = feedbin.tagVisibility()
    if Object.keys(visibility).length == 0
      visibility = feedbin.tagVisibility(feedbin.data.tag_visibility)
    for id, open of visibility
      tag = $(".feeds [data-tag-id=#{id}]")
      if open
        tag.addClass('open')

  reselect: ->
    if feedbin.selectedSource && feedbin.selectedTag
      $("[data-tag-id=#{feedbin.selectedTag}]").find("[data-feed-id=#{feedbin.selectedSource}]").addClass("selected")
      $("[data-tag-id=#{feedbin.selectedTag}][data-feed-id=#{feedbin.selectedSource}]").addClass("selected")
    else if feedbin.selectedSource
      $("[data-feed-id=#{feedbin.selectedSource}]").addClass("selected")

  fonts: (font) ->
    if !feedbin.fontsLoaded && feedbin.data && feedbin.data.font_stylesheet
      if $.inArray(font, ["sans-serif-1", "sans-serif-2", "serif-1", "serif-2"]) != -1
        loadCSS(feedbin.data.font_stylesheet)
        feedbin.fontsLoaded = true

  faviconColors: (target) ->
    $("[data-color-hash-seed]", target).each ->
      host = $(@).data("color-hash-seed")
      [hue, saturation, lightness] = feedbin.colorHash.hsl(host)
      color = feedbin.colorHash.hex(host)
      rotate = hue % 6
      translate = 25 - rotate

      $(@).css
        "background-color": color

      $('.favicon-inner', @).css
        "transform": "translate(-#{translate}%, -#{translate}%) rotate(#{hue}deg)"

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
    canvas.parentNode.removeChild(canvas)
    "rgba(#{data.data[0]}, #{data.data[1]}, #{data.data[2]}, #{data.data[3]})"

  darkMode: ->
    if "matchMedia" of window
      result = window.matchMedia('(prefers-color-scheme: dark)')
      if result && "matches" of result
        result.matches == true

  setNativeTheme: (calculateOverlay = false, timeout = 1) ->
    if feedbin.native && feedbin.data && feedbin.theme
      result = window.matchMedia('(prefers-color-scheme: dark)');
      statusBar = if $("body").hasClass("theme-dusk") || $("body").hasClass("theme-midnight") || result.matches == true then "lightContent" else "default"
      message = {
        action: "titleColor",
        statusBar: statusBar
      }
      sections = ["border", "body"]
      for section in sections
        color = $("[data-theme-#{section}]").css("backgroundColor")
        if calculateOverlay
          overlayColor = $("[data-theme-overlay]").css("backgroundColor")
          color = feedbin.calculateColor(color, overlayColor)

        ctx = document.createElement('canvas').getContext('2d')
        ctx.strokeStyle = color
        hex = ctx.strokeStyle
        message[section] = hex

      setTimeout ( ->
        feedbin.nativeMessage("performAction", message)
      ), timeout

  nativeMessage: (name, data) ->
    if typeof(webkit) != "undefined"
      if webkit.messageHandlers
        if handler = webkit.messageHandlers.feedbin || webkit.messageHandlers.turbolinksDemo
          handler.postMessage
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

  range: (element) ->
    start = element.offset().left
    width = element.outerWidth()
    end = start + width
    [start, end]

  inRange: (element, xCoordinate) ->
    range = feedbin.range element
    if xCoordinate >= range[0] && xCoordinate <= range[1]
      return true
    else
      return false

  scrollToTop: (xCoordinate) ->
    element = null
    sections = [$(".feeds"), $(".entries"), $(".entry-content")]

    for section in sections
      if section.length > 0 && feedbin.inRange(section, xCoordinate)
        element = section

    if element
      element.css
        "-webkit-overflow-scrolling": "auto"
      element.animate {scrollTop: 0}, {
        duration: 150,
        complete: ()->
          element.css
            "-webkit-overflow-scrolling": "touch"
      }

  jumpTemplate: ->
    if feedbin.jumpResultTemplate == null
      feedbin.jumpResultTemplate = $($('.modal [data-behavior~=result_template]').html())
    feedbin.jumpResultTemplate

  jumpResultItem: (title, icon, index = null) ->
    markup = feedbin.jumpTemplate().clone()
    markup.find('.text-wrap').html(title)
    markup.find('.icon-wrap').replaceWith(icon)
    markup.attr('data-index', index)
    markup

  jumpTo: (element) ->
    parent = element.closest('li')
    viewMode = feedbin.data.viewMode

    feedbin.reveal element, ->
      feedbin.data.viewMode = viewMode

  jumpMenu: ->
    feedbin.showModal("search", "Search")
    $("body").addClass("jump-search-empty")
    setTimeout ( ->
      $(".modal [data-behavior~=autofocus]").focus()
    ), 150

    options = []
    $('[data-jumpable]').each (index, element)->
      element = $(element)
      jumpable = element.data('jumpable')
      icon = element.find('.favicon-wrap').prop('outerHTML')
      markup = feedbin.jumpResultItem(jumpable.title, icon, index)
      options.push
        element: element
        jumpable: jumpable
        markup: markup
        action: () ->
          feedbin.jumpTo(element)

    feedbin.jumpOptions = options

  replaceModal: (target, body) ->
    modal = $(".#{target}")
    placeholderHeight = modal.find('.modal-dialog').outerHeight()
    body = $(body)
    body.css({height: "#{placeholderHeight}px"}).addClass('loading')

    modal.find('.modal-dialog').html(body)
    contentHeight = modal.find('.modal-content').outerHeight()

    modal.find('.modal-wrapper').addClass('loaded')

    if placeholderHeight != contentHeight
      windowHeight = window.innerHeight
      if windowHeight < contentHeight
        contentHeight = windowHeight - modal.find('.modal-dialog').offset().top
      modal.find('.modal-wrapper').css({height: "#{contentHeight}px"})

    setTimeout ( ->
      modal.find('.modal-wrapper').css({height: 'auto'})
      modal.find('.modal-wrapper').removeClass('loading')
      input = modal.find('[data-behavior~=autofocus]')
      if input.length
        input.focus()
        length = input.val().length
        input[0].setSelectionRange(length, length)
    ), 150

    setTimeout ( ->
      $("body").addClass("modal-replaced")
    ), 300


  modalContent: (target, body) ->
    modal = $(".#{target}")
    $(".modal-body", modal).html(body);

  mobileView: ->
    if $(window).width() <= 700
      true
    else
      false

  scrollToPanel: (selector, animate = true) ->
    containerClass = ".app-wrap"
    hasTwoPanels = $('body').hasClass('two-up')
    if hasTwoPanels
      containerClass = ".sidebar-column"
    offset = $(selector)[0].offsetLeft

    if animate
      timeout = 200
      feedbin.panelScrollComplete = false
      $(containerClass).css {'scroll-snap-type': 'unset'} if feedbin.aspectRatio
      $(containerClass).animate({scrollLeft: offset}, {duration: timeout})
      setTimeout ( ->
        feedbin.panelScrollComplete = true
      ), timeout

      setTimeout ( ->
        $(containerClass).css {'scroll-snap-type': 'x mandatory'}  if feedbin.aspectRatio
      ), timeout
    else
      $(containerClass).prop 'scrollLeft', offset

  showPanel: (panel, state = true) ->
    feedbin.panel = panel
    if panel == 1
      if state && feedbin.mobileView()
        window.history.pushState({panel: 1}, "", "/");
      $('body').addClass('nothing-selected').removeClass('feed-selected entry-selected')
      if feedbin.swipe && $('body').hasClass('has-offscreen-panels')
        feedbin.scrollToPanel('.feeds-column')

    else if panel == 2
      if state && feedbin.mobileView()
        window.history.pushState({panel: 2}, "", "/");
      $('body').addClass('feed-selected').removeClass('nothing-selected entry-selected')
      if feedbin.swipe && $('body').hasClass('has-offscreen-panels')
        feedbin.scrollToPanel('.entries-column')

    else if panel == 3
      if state && feedbin.mobileView()
        window.history.pushState({panel: 3}, "", "/");
      $('body').addClass('entry-selected').removeClass('nothing-selected feed-selected')
      if feedbin.swipe && $('body').hasClass('has-offscreen-panels')
        feedbin.scrollToPanel('.entry-column')

  hideNotification: (animated = true) ->
    container = $('[data-behavior~=notification_container]')
    if animated
      container.addClass('fade-out')
    else
      container.addClass('hide')

    callback = ->
      container.addClass('hide')
      container.removeClass('visible')
      container.removeClass('fade-out')
    setTimeout callback, 200

  showNotification: (text, error = false) ->
    clearTimeout(feedbin.notificationTimeout)

    container = $('[data-behavior~=notification_container]')
    content = $('[data-behavior~=notification_content]')

    if !container.hasClass('shake') && !container.hasClass('hide') && container.hasClass('error') && content.text() == text
      container.addClass('shake')
      callback = ->
        container.removeClass('shake')
      setTimeout callback, 600

    container.removeClass('error')
    container.removeClass('hide')
    container.addClass('visible')
    container.addClass('error') if error

    content.text(text)

    feedbin.notificationTimeout = setTimeout feedbin.hideNotification, 3000

  updateEntries: (entries) ->
    $('.entries [data-behavior~=entries_target]').html(entries)
    $('.entries').prop('scrollTop', 0)
    $(".entries").removeClass("loading");

  appendEntries: (entries) ->
    $('.entries [data-behavior~=entries_target]').append(entries)

  formatEntries: ->
    $(document).trigger('feedbin:entriesLoaded')
    feedbin.localizeTime()
    feedbin.applyUserTitles()
    feedbin.loadEntryImages()
    feedbin.faviconColors($(".entries-column"))

  updateUnreads: (unreadOnly, unreadEntries) ->
    if unreadOnly
      $.each unreadEntries, (index, unreadEntry) ->
        if feedbin.Counts.get().isRead(unreadEntry.id)
          feedbin.Counts.get().addEntry(unreadEntry.id, unreadEntry.feed_id, 'unread')
      feedbin.applyCounts(true);

  updatePager: (html) ->
    $('[data-behavior~=pagination]').html(html)

  entryChanged: ->
    if feedbin.previousEntry == null
      false
    else
      !feedbin.previousEntry || !feedbin.previousEntry.container.is(feedbin.selectedEntry.container)

  animateEntryContent: (content) ->
    innerContent = $('[data-behavior~=inner_content_target]')

    if $(feedbin.selectedEntry.container.closest("li")).isAfter(feedbin.previousEntry.container.closest("li"))
      next = $('<div class="next-entry load-next-entry"></div>')
      transitionClass = "slide-up"
    else
      next = $('<div class="previous-entry load-next-entry"></div>')
      transitionClass = "slide-down"

    $('.entry-toolbar').addClass("animate")

    next.html(content)

    next.insertAfter(innerContent)

    setTimeout ( ->
      next.removeClass("load-next-entry")
      $(".entry-content", innerContent).addClass(transitionClass)
    ), 1

    setTimeout ( ->
      $('.entry-toolbar').removeClass("animate")
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
    $("[data-behavior~=#{selector}] audio").each ->
      $(@).attr("controls", "controls")
      $(@).attr("preload", "none")

    $("video").each ->
      video = $(@)
      video.attr("controls", "true")
      containerClass = "media-container"
      unless video.closest(".#{containerClass}").length > 0
        container = $('<div>').addClass(containerClass)
        video.wrap container

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

      feedbin.formatIframes(content.find("[data-iframe-src]").not("[data-behavior~=iframe_placeholder]"))
      feedbin.formatTweets(content)
      feedbin.formatInstagram(content)

      content.find("video[data-camo-poster][data-canonical-poster]").each ->
        if feedbin.data.proxy_images
          src = 'camo-poster'
        else
          src = 'canonical-poster'
        $(@).attr("poster", $(@).data(src))
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

  applyUserTitles: (cached = true) ->
    textarea = document.createElement("textarea")
    selector = '[data-behavior~=user_title]'
    selector = "#{selector}:not(.renamed)" if cached
    $(selector).each ->
      element = $(@)
      feed = element.data('feed-id')
      if (feed of feedbin.data.user_titles)
        newTitle = feedbin.data.user_titles[feed]
        if element.prop('tagName') == "INPUT"
          textarea.innerHTML = newTitle
          element.val(textarea.value)
        else if element.is('[data-behavior~=feed_link]')
          data = element.data('mark-read')
          data.message = "Mark #{newTitle} as read?"
          element.data('mark-read', data)
        else if element.is('[data-behavior~=rename_target]')
          element.data('title', newTitle)
        else
          element.html(newTitle)
      if element.is('[data-jumpable]')
        jumpable = element.data('jumpable')
        jumpable["title"] = newTitle
        element.data('jumpable', jumpable)
      element.addClass('renamed')

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

  hash: (string) ->
    result = 0
    for i in [0..(string.length-1)]
      char = string.charCodeAt(i)
      result = ((result << 5) - result) + char
      result = result & result
    result

  readability: () ->
    feedId = feedbin.selectedEntry.feed_id
    entryId = feedbin.selectedEntry.id

    if feedbin.data.readability_settings[feedId] == true && feedbin.data.sticky_readability
      feedbin.automaticSubmit = true
      feedbin.changeContentView('extract')
      $('[data-behavior~=toggle_extract]').submit()

  resetScroll: ->
    $('.entry-content').prop('scrollTop', 0)

  fitVids: (target) ->
    target.fitVids({ customSelector: "iframe"});

  embed: (items, embed_url, urlFinder) ->
    if items.length > 0
      items.each ->
        item = $(@)
        url = urlFinder(item)
        if url
          id = feedbin.hash(url)
          item.attr("id", id)
          embedElement = feedbin.embeds["#{id}"]
          if embedElement
            item.replaceWith(embedElement.clone())
          else
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
    element = $('.entry-final-content .content-option')
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

  fullWidthImage: (img) ->
    load = ->
      width = img.get(0).naturalWidth
      if width > 528 && img.parents(".modal").length == 0
        img.addClass("full-width")
      img.addClass("show")

    if img.get(0).complete
      load()

    img.on 'load', (event) ->
      load()

  formatImages: (context = document) ->
    $("video[data-camo-poster]", context).each ->
      video = $(@)

      if feedbin.data.proxy_images
        src = 'camo-poster'
      else
        src = 'canonical-poster'

      actualSrc = video.data(src)
      if actualSrc?
        video.attr("poster", actualSrc)


    $("img[data-camo-src]", context).each ->
      img = $(@)

      if feedbin.data.proxy_images
        src = 'camo-src'
      else
        src = 'canonical-src'

      actualSrc = img.data(src)
      if actualSrc?
        img.attr("src", actualSrc)

      if img.is("[src*='feeds.feedburner.com'], [data-canonical-src*='feeds.feedburner.com']")
        img.addClass('hide')

      feedbin.fullWidthImage(img)

    $(".full-width-candidate", context).each ->
      feedbin.fullWidthImage $(@)

  removeOuterLinks: ->
    $('[data-behavior~=entry_final_content] a').find('video').unwrap()

  tooltips: ->
    $(document).tooltip
      selector: '[data-toggle="tooltip"]'
      delay:
        show: 400
        hide: 50

  preloadSiblings: ->
    return if feedbin.selectedEntry.container == null
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
      feedbin.removeOuterLinks()
      feedbin.formatIframes($("[data-iframe-src]").not("[data-behavior~=iframe_placeholder]"))
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
      feedbin.removeOuterLinks()
      feedbin.formatIframes($("[data-iframe-src]").not("[data-behavior~=iframe_placeholder]"))
      feedbin.formatTweets("[data-behavior~=view_link_markup_wrap]")
      feedbin.formatInstagram("[data-behavior~=view_link_markup_wrap]")
      feedbin.formatImages()
    catch error
      if 'console' of window
        console.log error

  autoUpdate: ->
    result = feedbin.refresh()
    if result
      result.always ->
        setTimeout feedbin.autoUpdate, 300000

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
    if feedbin.data && feedbin.data.font_sizes && feedbin.data.font_sizes[newFontSize]
      fontContainer.removeClass("font-size-#{currentFontSize}")
      fontContainer.addClass("font-size-#{newFontSize}")
      fontContainer.data('font-size', newFontSize)
      $('[data-behavior~=font_size]').val(newFontSize)

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

    if feedbin.markReadData.type == "feed"
      feedbin.Counts.get().markFeedRead(feedbin.markReadData.data)
      feedbin.applyCounts(true)
    else if feedbin.markReadData.type == "tag"
      feedbin.Counts.get().markTagRead(feedbin.markReadData.data)
      feedbin.applyCounts(true)
    else if feedbin.markReadData.type == "all" || feedbin.markReadData.type == "unread"
      feedbin.Counts.get().markAllRead()
      feedbin.applyCounts(false)

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

  isFullScreen: ->
    $('body').hasClass('full-screen')

  nextEntry: ->
    nextEntry = $('.entries').find('.selected').next()
    if nextEntry.length
      nextEntry
    else
      null

  nextEntryPreview: () ->
    return if feedbin.selectedEntry.container == null
    next = feedbin.selectedEntry.container.parents('li').next()
    if next.length
      title = next.find('.title').first().text()
      feed = next.find('.feed-title').first().text()
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
    scroll = item.offset().top - container.offset().top + container.scrollTop()
    container.animate {
      scrollTop: scroll
    }, 200

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

  showSearchControls: (sort, query, savedSearchPath, message) ->
    text = null
    if sort
      text = $("[data-sort-option=#{sort}]").text()
    if !text
      text = $("[data-sort-option=desc]").text()
    $('body').addClass('show-search-options')
    $('body').addClass('feed-selected').removeClass('nothing-selected entry-selected')
    $('.sort-order').text(text)
    $('.search-control').removeClass('edit')
    $('.saved-search-wrap').removeClass('show')
    $('[data-behavior~=save_search_link]').removeAttr('disabled')
    $('[data-behavior~=new_saved_search]').attr('href', savedSearchPath)
    feedbin.markReadData =
      type: "search"
      data: query
      message: message

  readabilityActive: ->
    $('[data-behavior~=toggle_extract]').find('.active').length > 0

  prepareShareForm: ->
    $('.field-cluster input, .field-cluster textarea').val('')
    $('.sharing-controls [type="checkbox"]').attr('checked', false);

    title = $('.entry-header h1').first().text()
    $('.share-form .title-placeholder').val(title)

    url = $('.entry-header a').first().attr('href')
    $('.share-form .url-placeholder').val(url)

    description = feedbin.getSelectedText()
    url = $('#source_link').attr('href')
    $('.share-form .description-placeholder').val("#{description}")

    if description != ""
      $('[data-basement-panel-target="micro_blog_share_panel"] .share-form .description-placeholder').val("#{description} #{url}")
    else
      $('[data-basement-panel-target="micro_blog_share_panel"] .share-form .description-placeholder').val("#{url}")


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
    $('.entry-content').each ->
      @.style.removeProperty("top")

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
    newTop = selectedPanel.children(":first").outerHeight()
    $('.entry-content').css
      "top": "#{newTop}px"
    selectedPanel.prop('scrollTop', 0)

  applyStarred: (entryId) ->
    if feedbin.Counts.get().isStarred(entryId)
      $('[data-behavior~=selected_entry_data]').addClass('starred')

  showEntry: (entryId) ->
    try
      entry = feedbin.entries[entryId]
      $('body').removeClass('extract-active')
      feedbin.updateEntryContent(entry.content, entry.inner_content)
      feedbin.formatEntryContent(entryId, true)
      if feedbin.viewType == 'updated'
        $('[data-behavior~=change_content_view][data-view-mode=diff]').prop('checked', true).change()
      else if feedbin.data.subscription_view_mode[entry.feed_id] == "newsletter"
        $('[data-behavior~=change_content_view][data-view-mode=newsletter]').prop('checked', true).change()
    catch error
      console.log ["error showing article", error]


  tagFeed: (url, tag, noResponse = true) ->
    $.ajax
      type: "POST",
      url: url,
      data: {
        _method: "patch",
        "tag_name[]": tag
        no_response: noResponse
      }

  hideEmptyTags: ->
    $('[data-tag-id]').each ->
      if $(@).find('ul li').length == 0
        $(@).remove()

  sort: (target) ->
    $('> [data-behavior~=sort_feed]', target).sort(feedbin.sortByFeedOrder).detach().appendTo(target)

  sortFeeds: ->
      $('.drawer ul').each ->
        feedbin.sort $(@)
      feedbin.sort $('[data-behavior~=feeds_target]')

  resort: (order) ->
    feedbin.data.feed_order = order
    feedbin.sortFeeds()

  appendTag: (target, ui) ->
    appendTarget = target.find('ul').first()
    ui.helper.remove()
    ui.draggable.appendTo(appendTarget)
    feedbin.sortFeeds()

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

  hideSubscribeResults: ->
    $('.modal-purpose-subscribe .modal-body, .modal-purpose-subscribe .modal-footer').hide()
    $('.modal-purpose-subscribe .modal-dialog').removeClass('done');
    $('[data-behavior~=feeds_search_favicon_target]').html('')
    $('.modal-purpose-subscribe [data-behavior~=subscribe_target]').html('')

  showSubscribeResults: ->
    $('.modal-purpose-subscribe .modal-body, .modal-purpose-subscribe .modal-footer').slideDown(200)
    $('.modal-purpose-subscribe .modal-dialog').addClass('done');
    $('.modal-purpose-subscribe [data-behavior~=submit_add]').removeAttr('disabled');
    $('.modal-purpose-subscribe .title').first().find("input").focus();
    $('.modal-purpose-subscribe .password-footer').addClass('hide')
    $('.modal-purpose-subscribe .subscribe-footer').removeClass('hide')

  showAuthField: (html) ->
    $('.modal-purpose-subscribe [data-behavior~=subscribe_target]').html(html);
    $('.modal-purpose-subscribe .modal-body, .modal-purpose-subscribe .modal-footer').slideDown(200)
    $('.modal-purpose-subscribe .modal-dialog').addClass('done');
    $('.modal-purpose-subscribe .password-footer').removeClass('hide')
    $('.modal-purpose-subscribe .subscribe-footer').addClass('hide')
    window.history.replaceState({}, document.title, "/");

  basicAuthForm: ->
    $('.modal-purpose-subscribe [data-behavior~=submit_add]').removeAttr('disabled')
    $('.modal-purpose-subscribe #basic_username').focus()

  showModal: (target, title = null) ->
    modal = $("#modal")
    classes = modal[0].className.split(/\s+/)
    classPrefix = "modal-purpose"
    modalClass = "#{classPrefix}-#{target}"

    content = $($("[data-modal-purpose=#{target}]").html())

    titleElement = content.find(".modal-title")
    if title
      titleElement.text(title)

    $.each classes, (index, className) ->
      if className.indexOf(classPrefix) != -1
        modal.removeClass className

    modal.html(content)
    modal.addClass(modalClass)
    modal.modal('show')
    modalClass

  loadLink: (href) ->
    feedbin.showModal("view_link");
    $.get(feedbin.data.modal_extracts_path, {url: href});

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

      if width < 700
        $(".entry-column").addClass("constrained")
      else
        $(".entry-column").removeClass("constrained")

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

  linkActions: {}

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

    columnCount: ->
      sidebarClassName = 'sidebar-column'

      $(document).on "feedbin:panels:one", (event) ->
        $(".#{sidebarClassName}").contents().unwrap()

      $(document).on "feedbin:panels:two", (event) ->
        if $('.sidebar-column').length == 0
          $(".feeds-column, .entries-column").wrapAll("<div class='#{sidebarClassName}' />")

      $(document).on "feedbin:panels:three", (event) ->
        $(".#{sidebarClassName}").contents().unwrap()

    throttledResize: ->
      resize = ->
        $(document).trigger("window:throttledResize")
      $(window).on('resize', _.throttle(resize, 100))

    panels: ->
      feedbin.panelCount()
      $(window).on('window:throttledResize', feedbin.panelCount);

    baseFontSize: ->
      element = document.createElement('div')
      content = document.createTextNode('content')
      element.appendChild content
      element.style.display = 'none'
      element.style.font = '-apple-system-body'

      if element.style.font != "" && "ontouchend" of document
        document.body.appendChild element
        style = window.getComputedStyle(element, null)
        size = style.getPropertyValue 'font-size'
        base = parseInt(size) - 1
        element.parentNode.removeChild(element)
      else
        base = "16"

      $("html").css
        "font-size": "#{base}px"

    faviconColors: ->
      feedbin.faviconColors($("body"))

    hasShadowDOM: ->
      if feedbin.hasShadowDOM
        $('body').addClass('shadow-dom')

    hasScrollBars: ->
      if feedbin.scrollBars()
        $('body').addClass('scroll-bars')

    hasScrollSnap: ->
      if 'scroll-snap-type' of document.body.style
        feedbin.swipe = true
        $('body').addClass('swipe')

    hasSmoothScrolling: ->
      if typeof(CSS) != "undefined" && CSS.supports("scroll-behavior", "smooth")
        feedbin.smoothScroll = true
        $('body').addClass('smooth-scroll')

    hasAspectRatio: ->
      if typeof(CSS) != "undefined" && CSS.supports("aspect-ratio", "1")
        feedbin.aspectRatio = true
        $('body').addClass('aspect-ratio')

    hasTouch: ->
      if 'ontouchstart' of document
        $('body').addClass('touch')
      else
        $('body').addClass('no-touch')

    isStandalone: ->
      ipad = (navigator.userAgent.match(/iPad/i) != null)

      if ipad || 'standalone' of window.navigator && window.navigator.standalone
        $('body').addClass('standalone-navigator')

    initSingletons: ->
      new feedbin.CountsBehavior()

    state: ->
      $(window).on 'popstate', (event) ->
        panel = 1
        if event.originalEvent.state && "panel" of event.originalEvent.state
          panel = event.originalEvent.state.panel
        feedbin.showPanel(panel, false)

    userTitles: ->
      feedbin.applyUserTitles()

    renameFeed: ->
      $(document).on 'dblclick', '[data-behavior~=renamable]', (event) ->
        unless feedbin.isRelated('.feed-action-button', event.target)
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

          target.closest('li').append(form)

          input.select()

      $(document).on 'submit', '[data-behavior~=rename_form]', (event, xhr) ->
        input = $(@).find('[data-behavior~=rename_input]')
        container = $(@).closest('li').find('> [data-behavior~=renamable]')
        title = container.find('[data-behavior~=rename_title]')
        target = container.find('[data-behavior~=rename_target]')
        target.data('title', input.val())
        title.text(input.val())
        $('[data-behavior~=rename_form]').remove()
        $('[data-behavior~=rename_title]').removeClass('hide')

      $(document).on 'blur', '[data-behavior~=rename_input]', (event) ->
        $('[data-behavior~=rename_form]').remove()
        $('[data-behavior~=rename_title]').removeClass('hide')

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

    feedSettingsButton: ->
      $(document).on 'click', '[data-behavior~=show_entries]', (event) ->
        element = $(@)
        button = $('[data-behavior~=feed_settings]')
        if element.is('[data-behavior~=has_settings]')
          button.attr('href', element.data('settings-path'))
          button.removeAttr('disabled')
        else
          button.attr('disabled', 'disabled')

    selected: ->
      $(document).on 'ajax:success', '[data-behavior~=show_entries]', (event) ->
        target = $(event.target)
        unless target.is('[data-behavior~=toggle_drawer]')
          feedbin.selectedSource = target.closest('[data-feed-id]').data('feed-id')
          feedbin.selectedTag = target.closest('[data-tag-id]').data('tag-id')

    setViewMode: ->
      $(document).on 'ajax:beforeSend', '[data-behavior~=show_entries]', (event, xhr, settings) ->
        settings.url = "#{settings.url}?view_mode=#{feedbin.data.viewMode}"

    clearEntry: ->
      $(document).on 'ajax:beforeSend', '[data-behavior~=show_entries]', (event) ->
        unless $(event.target).is('[data-behavior~=feed_action_parent]')
          feedbin.clearEntry()
        return

    cancelFeedRequest: ->
      $(document).on 'ajax:beforeSend', '[data-behavior~=show_entries]', (event, xhr) ->
        if $(event.target).is("[data-behavior~=feed_action_parent]")
          return

        if feedbin.feedXhr
          feedbin.feedXhr.abort()
        if $(event.target).is('.edit_feed')
          feedbin.feedXhr = null
        else
          feedbin.feedXhr = xhr
        return

    loadEntries: ->
      link = $('[data-behavior~=feeds_target] li:visible').first().find('a')
      mobile = $('body').hasClass('mobile')
      if link.length > 0 && !mobile
        link[0].click()

    resizeWindow: ->
      feedbin.measureEntryColumn()
      $(window).on "window:throttledResize", feedbin.measureEntryColumn

    resizeColumns: ->
      measure = _.throttle(feedbin.measureEntryColumn, 100);

      defaults =
        handles: "e"
        minWidth: 200
        resize: (event, ui) ->
          measure()
        stop: (event, ui) ->
          column = $(ui.element).data('resizable-name')
          fieldName = "#{column}_width"
          field = $("[data-behavior~=#{fieldName}]")
          field.val(ui.size.width)
          field.closest('form').submit()

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
        feedId = $(@).data('feed-id')
        $(".entries").addClass("loading")
        title = $(".collection-label-wrap", @).text()
        titleContainer = $("[data-behavior~=entries_header] .feed-title-wrap [data-behavior~=user_title]")
        titleContainer.text(title)
        if feedId
          titleContainer.data('feed-id', feedId)
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

    sortFeeds: ->
      feedbin.sortFeeds()

    showFormatMenu: ->
      $(document).on 'click', (event) ->
        menu = $('.format-palette')
        button = $('[data-behavior~=show_format_menu]')
        if !feedbin.isRelated(menu, event.target) && !feedbin.isRelated(button, event.target) && feedbin.formatMenu
          feedbin.formatMenu.destroy()
          feedbin.formatMenu = null
          menu.addClass('hide')

      $(document).on 'click', '[data-behavior~=show_format_menu]', (event) ->
        $('.dropdown-wrap.open').removeClass('open')
        button = $(event.currentTarget)
        menu = $('.format-palette')
        if feedbin.formatMenu
          feedbin.formatMenu.destroy()
          feedbin.formatMenu = null
          menu.addClass('hide')
        else
          options = {
            placement: 'bottom',
            modifiers: {
              preventOverflow: {
                padding: 7
              },
              offset: {
                offset: "0, -5"
              },
              flip: {
                enabled: false
              },
            }
          }
          feedbin.formatMenu = new Popper(button, menu, options)
          menu.removeClass('hide')
          event.stopPropagation()

    linkActions: ->
      $(document).on 'click', '[data-behavior~=add_to_pages]', (event) ->
        tooltip = $(@).closest("[data-behavior~=link_actions]")
        tooltip.addClass('hide')
        href = tooltip.data('url')
        $.post(feedbin.data.pages_internal_path, {url: href});
        event.preventDefault()

      $(document).on 'click', '[data-behavior~=view_link]', (event) ->
        tooltip = $(@).closest("[data-behavior~=link_actions]")
        tooltip.addClass('hide')
        href = tooltip.data('url')
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
          $(@).addClass('dropdown-right')
        else
          $(@).addClass('dropdown-left')
        event.preventDefault()

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

      $(document).on 'click', '[data-behavior~=view_mode_dropdown]', (event) ->
        dropdown = $(@)
        if dropdown.hasClass('open')
          width = 200
          feedsWidth = $('.feeds-column').outerWidth()
          width = feedsWidth - 16 if feedsWidth > width
          $('.dropdown-content', dropdown).css({width: "#{width}px"})

    drawer: ->
      feedbin.setTagVisibility()
      $(document).on 'submit', '[data-behavior~=toggle_drawer]', (event) =>
        container = $(event.currentTarget).closest('[data-tag-id]')
        open = !container.hasClass("open")
        id = container.data('tag-id')

        visibility = feedbin.tagVisibility()
        visibility[id] = open
        feedbin.tagVisibility(visibility)

        container.toggleClass('open')
        container.addClass('animate')

        drawer = container.find('.drawer')

        if open
          windowHeight = window.innerHeight
          targetHeight = $('ul', drawer).height()
          if windowHeight < targetHeight
            targetHeight = windowHeight - drawer.offset().top
          height = targetHeight
        else
          height = 0
          drawer.css
            height: targetHeight

        drawer.animate {
          height: height
        }, 150, ->
          container.removeClass('animate')
          if height > 0
            drawer.css
              height: 'auto'

        event.stopPropagation()
        event.preventDefault()
        return

    feedAction: ->
      $(document).on 'click', '[data-behavior~=feed_action]', (event) =>
        $(event.currentTarget).closest('form').submit()
        event.currentTarget.blur()
        event.stopPropagation()
        event.preventDefault()

    feedActions: ->
      $(document).on 'change', '[data-behavior~=feed_actions]', (event) ->
        operation = $(@).val()
        if operation != ""
          $(@).closest('form').submit()

    checkBoxToggle: ->
      $(document).on 'change', '[data-behavior~=include_all]', (event) ->
        if $(@).is(':checked')
          $('[data-behavior~=toggle_checked_target] [type="checkbox"][name]').prop('checked', true).change()
          $('[data-behavior~=toggle_checked_target] [type="checkbox"][name]').prop('disabled', true)
        else
          $('[data-behavior~=toggle_checked_target] [type="checkbox"][name]').prop('disabled', false)

      $(document).on 'change', '[data-behavior~=toggle_checked]', (event) ->
        $('[data-behavior~=toggle_checked_hidden]').toggleClass('hide')
        $('[data-behavior~=toggle_checked_hidden] [type="checkbox"]').prop('checked', false).change()
        if $(@).is(':checked')
          $('[data-behavior~=toggle_checked_target] [type="checkbox"][name]').prop('checked', true).change()
        else
          $('[data-behavior~=toggle_checked_target] [type="checkbox"][name]').prop('checked', false).change()
        event.preventDefault()
        return

      $(document).on 'change', '[data-behavior~=enable_control]', (event) ->
        if $('[data-behavior~=enable_control]:checked').length == 0
          $('[data-behavior~=enable_control_target]').prop('disabled', true)
        else
          $('[data-behavior~=enable_control_target]').prop('disabled', false)

      $(document).on 'change', '[data-behavior~=check_feeds]', (event) ->
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
      feedbin.timeago()

    updateReadability: ->
      $(document).on 'ajax:complete', '[data-behavior~=toggle_extract]', (event, xhr) ->
        feedbin.readabilityXHR = null;
        $('.button-toggle-content').removeClass('loading')

      $(document).on 'ajax:beforeSend', '[data-behavior~=toggle_extract]', (event, xhr) ->
        entry = $(@).data('entry-id')

        if feedbin.automaticSubmit != true
          $.post($(@).data("sticky-url"))
        feedbin.automaticSubmit = false

        if entry of feedbin.extractCache
          xhr.abort()

          if feedbin.readabilityActive()
            feedbin.changeContentView(feedbin.previousContentView)
          else
            $("[data-content-option~=extract]").html(feedbin.extractCache["#{entry}"]);
            feedbin.formatEntryContent(entry, false, false);
            feedbin.changeContentView('extract')

        else if feedbin.readabilityXHR
          feedbin.readabilityXHR.abort()
          xhr.abort()

          feedbin.readabilityXHR = null
          $('.button-toggle-content').removeClass('loading')

          feedbin.changeContentView('default')
        else
          $('.button-toggle-content').addClass('loading')
          feedbin.readabilityXHR = xhr

        if feedbin.readabilityActive()
          $('.button-toggle-content').removeClass('active')
          $("#extract").val("true")
        else
          $('.button-toggle-content').addClass('active')
          $("#extract").val("false")

        true

    autoUpdate: ->
      setTimeout feedbin.autoUpdate, 300000

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
      $('[data-behavior~=change_font]').change ->
        fontContainer = $("[data-font]")
        currentFont = fontContainer.data('font')
        newFont = $(@).val()
        fontContainer.removeClass("font-#{currentFont}")
        fontContainer.addClass("font-#{newFont}")
        fontContainer.data('font', newFont)
        feedbin.fonts(newFont)

    fontSize: ->
      $(document).on 'click', '[data-behavior~=increase_font]', (event) ->
        feedbin.updateFontSize('increase')
        return

      $(document).on 'click', '[data-behavior~=decrease_font]', (event) ->
        feedbin.updateFontSize('decrease')
        return

    entryWidth: ->
      $(document).on 'change', '[data-behavior~=entry_width]', (event) ->
        onClass = "fluid-1"
        offClass = "fluid-0"
        target = $('[data-behavior~=entry_content_target], body')
        if $(event.target).is(':checked')
          target.removeClass('fluid-0').addClass('fluid-1')
        else
          target.removeClass('fluid-1').addClass('fluid-0')

    fullscreen: ->
      $(document).on 'click', '[data-behavior~=full_screen]', (event) ->
        $('[data-behavior~=toggle_full_screen]').click()

      $(document).on 'change', '[data-behavior~=toggle_full_screen]', (event) ->
        $('body').toggleClass('full-screen')
        if !$('body').hasClass('full-screen')
          feedbin.scrollToPanel('.entries-column', false)
          window.history.replaceState({}, "", "/");
          document.title = "Feedbin"
          feedbin.updateTitle()
        feedbin.measureEntryColumn()
        feedbin.setNativeBorders()

    theme: ->
      $(document).on 'click', '[data-behavior~=switch_theme]', (event) ->
        theme = $(@).val()
        $('[data-behavior~=class_target]').removeClass('theme-day')
        $('[data-behavior~=class_target]').removeClass('theme-sunset')
        $('[data-behavior~=class_target]').removeClass('theme-dusk')
        $('[data-behavior~=class_target]').removeClass('theme-midnight')
        $('[data-behavior~=class_target]').removeClass('theme-auto')
        $('[data-behavior~=class_target]').addClass("theme-#{theme}")

    titleBarColor: ->
      feedbin.setNativeTheme()
      $(document).on 'click', '[data-behavior~=switch_theme]', (event) ->
        feedbin.setNativeTheme()

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
        $('.dropdown-wrap.open').removeClass('open')
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

    feedsSearch: ->
      $(document).on 'submit', '[data-behavior~=feeds_search]', ->
        feedbin.hideSubscribeResults()

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
        feedbin.showNotification('Search error.', true);
        return

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

    serviceOptions: ->
      open = (container, height) ->
        callback = -> container.addClass('fully-open')
        setTimeout callback, 200
        container.addClass('open').css
          height: height

      close = (container, height) ->
        container.removeClass('fully-open')
        container.removeClass('open')
        container.css
          height: 0

      $(document).on 'click', '[data-behavior~=toggle_service_options]', (event) ->
        height = $(@).parents('li').find('.service-options').outerHeight()
        container = $(@).closest('li').find('.service-options-wrap')
        if container.hasClass('open')
          close(container, height)
        else
          open(container, height)
        event.preventDefault()

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
          appendTo: field.closest("[data-behavior~=autocomplete_parent]").find("[data-behavior=autocomplete_target]")
          delimiter: /(,)\s*/
          deferRequestBy: 50
          autoSelectFirst: true

    nativeResize: ->
      if feedbin.native
        feedbin.setNativeBorders()
        $(window).on 'resize', () ->
          feedbin.setNativeBorders()

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
        $(window).on('window:throttledResize', resize);
        resize()

    tumblrType: ->
      $(document).on 'change', '[data-behavior~=tumblr_type]', ->
        type = $(@).val()
        description = $(@).find("option:selected").data('description-name')
        typeText = $(@).find("option:selected").text()
        if type == 'quote'
          $('.share-form .source-placeholder-wrap').removeClass('hide')
          $('.share-form .title-placeholder-wrap').addClass('hide')
        else
          $('.share-form .source-placeholder-wrap').addClass('hide')
          $('.share-form .title-placeholder-wrap').removeClass('hide')

        $('.share-form .type-text').text(typeText)
        $('.share-form .description-placeholder').attr('placeholder', description)

    dragAndDrop: ->
      feedbin.droppable()
      feedbin.draggable()

    selectCategory: ->
      $(document).on 'click', '[data-behavior~=selected_category]', (event) ->
        $(@).find('[data-behavior~=categories]').toggleClass('hide')

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
      cacheLink = (link) ->
        unless link.is("[data-link-cached]")
          link.attr('data-link-cached', "true")
          url = link.attr('href')
          form = $("[data-behavior~=extract_cache_form]")
          $("#url", form).val(url)
          form.submit()

      showLinkActions = (url, link) ->
        if url of feedbin.linkActions
          feedbin.linkActions[url].tooltip.removeClass('hide')

      $(document).on 'click', '[data-behavior~=open_item]', (event) ->
        feedbin.hideLinkActions()

      $(document).on 'mouseleave', '[data-behavior~=link_actions]', (event) ->
        url = $(@).data('url')
        setTimeout((-> feedbin.hideLinkAction(url)), 350)

      $(document).on 'mouseenter mouseleave', 'body:not(.touch) .entry-final-content a', (event) ->
        link = $(@)
        url = link.attr('href')

        if event.type == "mouseenter" && url of feedbin.linkActions
          clearTimeout(feedbin.linkActions[url].linkActionsTimer)
          clearTimeout(feedbin.linkActions[url].linkCacheTimer)

        if link.text().trim().length > 0 && !$(@).has('.mejs__container').length > 0 && !link.closest(".system-content").length && !link.closest(".bigfoot-footnote").length
          if event.type == "mouseleave"
            setTimeout((-> feedbin.hideLinkAction(url)), 200)

          if event.type == "mouseenter"
            unless url of feedbin.linkActions
              tooltip = $('[data-behavior~=link_actions_template] [data-behavior~=link_actions]').clone()
              tooltip.data('url', url)
              $('body').append(tooltip)
              position = link[0].getClientRects()
              lastLine = position[position.length - 1]
              offset = (lastLine.width + tooltip.outerWidth()) * -1
              options =
                placement: 'right-end'
                modifiers:
                  preventOverflow:
                    enabled: false
                  offset:
                    offset: "-2, #{offset}"

              feedbin.linkActions[url] =
                linkActionsTimer: null
                linkCacheTimer: null
                popper: new Popper(link, tooltip, options)
                tooltip: tooltip

            feedbin.linkActions[url].linkCacheTimer = setTimeout((-> cacheLink(link)), 100)
            feedbin.linkActions[url].linkActionsTimer = setTimeout((-> showLinkActions(url, link)), 250)


    loadLinksInApp: ->
      $(document).on 'click', '[data-behavior~=entry_final_content] a', (event) ->
        newTab = (event.ctrlKey || event.metaKey)
        if feedbin.data.view_links_in_app && !feedbin.isRelated(".link-actions", event.target) && !newTab
          href = $(@).attr('href')
          feedbin.loadLink(href)
          event.preventDefault()

    openModal: ->
      $(document).on 'click', '[data-behavior~=open_modal]', (event) ->
        target = $(@).data("modal-target")
        title = $(@).data("modal-title")
        feedbin.showModal(target, title)

    settingsModal: ->
      $(document).on 'click', '[data-behavior~=open_settings_modal]', (event) ->
        unless $(@).is('[disabled]')
          feedbin.showModal('edit')

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
        if !feedbin.isRelated('.embed-link', event.target)
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
          feedbin.setNativeBorders("back")
          feedbin.setNativeTheme(true)

      $(document).on 'shown.bs.modal', () ->
        feedbin.faviconColors($(".modal"))
        setTimeout ( ->
          $("body").addClass("modal-shown")
        ), 150

      $(document).on 'hide.bs.modal', () ->
        $("body").removeClass("modal-shown")
        $("body").removeClass("modal-replaced")
        feedbin.setNativeBorders()
        feedbin.setNativeTheme(false, 160)

    modalScrollPosition: ->
      $(document).on 'hide.bs.modal', (event) ->
        $("body").removeClass("modal-top")
        $("body").removeClass("modal-bottom")

      $(document).on 'shown.bs.modal', (event) ->
        $("body").removeClass("modal-top")
        $("body").removeClass("modal-bottom")

      $('.modal').on 'scroll', (event) ->
        modalHeader = $('.modal .modal-content').get(0)
        if modalHeader
          modalAtTop = modalHeader.getBoundingClientRect().top <= 0
          if modalAtTop
            $("body").addClass("modal-top")
          else
            $("body").removeClass("modal-top")

        modalFooter = $('.modal .modal-footer').get(0)
        if modalFooter
          modalAtBottom = modalFooter.getBoundingClientRect().bottom == $('body').get(0).getBoundingClientRect().bottom
          if modalAtBottom
            $("body").addClass("modal-bottom")
          else
            $("body").removeClass("modal-bottom")

    viewModeEffects: ->
      scrollStop = $('.view-mode').css("top")
      scrollStop = Math.abs(parseInt(scrollStop))

      scrollStopAlt = $('.feeds .view-mode').outerHeight() - 25

      scrolled = (element) ->
        return if element.length == 0
        top = $(element)[0].scrollTop
        if top > scrollStop
          $('body').addClass('feed-scrolled')
        else
          $('body').removeClass('feed-scrolled')

        if top > scrollStopAlt
          $('body').addClass('feed-scrolled-alt')
        else
          $('body').removeClass('feed-scrolled-alt')

      $(window).on 'window:throttledResize', (event) ->
        scrolled($('.feeds'))

      $('.feeds').on 'scroll', (event) ->
        scrolled(@)

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
      $(document).on 'feedbin:native:statusbartouched', (event, xCoordinate) ->
        feedbin.scrollToTop(xCoordinate)

    disableSubmit: ->
      $(document).on 'submit', '[data-behavior~=disable_on_submit]', (event) ->
        $('[type=submit]', @).attr('disabled', 'disabled')

    showContainer: ->
      $(document).on 'click', '[data-behavior~=show_container]', (event) ->
        target = $(@).data('target')
        $("[data-container~=#{target}]").slideToggle("fast")
        event.preventDefault()

    toggleSearch: ->
      $(document).on 'click', '[data-behavior~=toggle_search]', (event) ->
        feedbin.toggleSearch()

    showApp: ->
      $('.app-wrap').addClass('show')
      $('.loading-app').addClass('hide')
      $('.feeds').addClass('show')

    jumpTo: ->
      $(document).on 'submit', '[data-behavior~=jump_search]', (event) ->
        target = $('.modal [data-behavior~=results_target]')
        selected = $('.selected', target)
        if selected.length > 0
          selected.click()
        else
          $('[data-behavior~=jump_to]', target).first().click()

        event.preventDefault()

      $(document).on 'mouseleave', '[data-behavior~=jump_to]', (event) ->
        $(@).removeClass('selected')

      $(document).on 'mouseenter', '[data-behavior~=jump_to]', (event) ->
        target = $('.modal [data-behavior~=results_target]')
        $('.selected', target).removeClass('selected')
        $(@).addClass('selected')

      $(document).on 'click', '[data-behavior~=jump_to]', (event) ->
        $('.modal').modal('hide')
        if action = $(@).data('action')
          action()
        else
          index = $(@).data('index')
          feedbin.jumpOptions[index].action()

    jumpMenu: ->
      $(document).on 'keyup', '[data-behavior~=jump_menu]', (event) ->

        # Don't run on arrow up or down
        return if event.keyCode == 38 || event.keyCode == 40

        template = feedbin.jumpTemplate()

        query = $(@).val()
        target = $('.modal [data-behavior~=results_target]')

        if query.length > 0
          $('body').removeClass('jump-search-empty')

          results = _.filter feedbin.jumpOptions, (option) ->
            titleFolded = option.jumpable.title.foldToASCII()
            queryFolded = query.foldToASCII()
            option.score = titleFolded.score(queryFolded)
            option.score > 0

          results = _.sortBy results, (option) ->
            -option.score

          results = _.groupBy results, (option) ->
            option.jumpable.section

          output = []
          _.each results, (value, key) ->
            output.push $("<li class='source-section'>#{key}</li>")
            output = output.concat(_.pluck(value, 'markup'))

          search = feedbin.jumpResultItem("#{query}", '<span class="favicon-wrap collection-favicon"><svg width="16" height="16" class="icon-search"><use xlink:href="#icon-search"></use></svg></span>')
          search.data 'action', () ->
            feedbin.showSearch(query)
            $('[data-behavior~=search_form]').submit()

          output.unshift search
          output.unshift $("<li class='source-section'>Search</li>")

          target.html(output)

          if target.find('.selected').length == 0
            target.find('[data-behavior~=jump_to]').first().addClass('selected')

        else
          $('body').addClass('jump-search-empty')
          target.html('')

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

    tooltips: ->
      feedbin.tooltips()

    closeMessage: ->
      $(document).on 'click', '[data-behavior~=close_message]', (event) ->
        feedbin.hideNotification(false)

    unsubscribe: ->
      $(document).on 'click', '[data-behavior~=unsubscribe]', (event) ->
        $('.modal').modal('hide')
        feed = $(@).data('feed-id')
        if (feedbin.data.viewMode != 'view_starred')
          $(".feeds [data-feed-id=#{feed}]").remove()
        $(".entries .feed-id-#{feed}").remove()
        feedbin.Counts.get().markFeedRead(feed)
        feedbin.applyCounts(false)
        feedbin.showPanel(1)
        feedbin.updateEntryContent('');
        feedbin.disableMarkRead()
        feedbin.hideSearch()
        $('[data-behavior~=feed_settings]').attr('disabled', 'disabled')
        $('body').addClass('nothing-selected').removeClass('feed-selected entry-selected')

    profiles: ->
      $(document).on 'click', (event, xhr) ->
        if $(event.target).closest('[data-behavior~=author_profile]').length == 0 && $(event.target).closest('[data-behavior~=toggle_profile]').length == 0
          $('[data-behavior~=author_profile]').addClass('hide')

      $(document).on 'click', '[data-behavior~=toggle_profile]', (event) ->
        element = $(event.currentTarget).closest('[data-behavior~=author_profile_wrap]').find('[data-behavior~=author_profile]')
        feedbin.faviconColors(element)
        element.toggleClass('hide')

    changeContentView: ->
      $(document).on 'change', '[data-behavior~=change_content_view]', (event) ->
        if $(@).is(':checked')
          mode = $(@).data('view-mode')
          feedbin.changeContentView(mode)
        else
          feedbin.changeContentView('default')

    hideTooltips: ->
      $(document).on 'click', '[data-toggle="tooltip"]', (event) ->
        $(@).tooltip('hide')

    colorSchemePreference: ->
      darkModeMediaQuery = window.matchMedia('(prefers-color-scheme: dark)')
      darkModeMediaQuery.addListener (event) ->
          setTimeout feedbin.setNativeTheme, 300

    visibilitychange: ->
      $(document).on 'visibilitychange', (event) ->
        if feedbin.native && document.hidden == false
          setTimeout feedbin.setNativeTheme, 300
          feedbin.refresh()

    toggleText: ->
      $(document).on 'click', '[data-toggle-text]', (event) ->
        button = $(@)
        text = button.text()
        newText = button.data('toggle-text')
        button.text(newText)
        button.data('toggle-text', text)

    scrollStarted: ->
      $(document).on 'click', '[data-behavior~=show_entries]', (event) ->
        feedbin.scrollStarted = false

    dataTooltip: ->
      $(document).on 'mouseout', '[data-behavior~=hide_tooltip]', (event) ->
        target = event.currentTarget
        controller = $(target).closest('[data-behavior~=tooltip_controller]')
        tooltipTarget = $('[data-behavior~=tooltip_target]', controller)
        tooltipTarget.addClass("hide")

      $(document).on 'mouseover', '[data-behavior~=show_tooltip]', (event) ->
        bar = event.currentTarget
        parentWidth = bar.offsetParent.offsetWidth

        controller = $(bar).closest('[data-behavior~=tooltip_controller]')
        tooltipTarget = $('[data-behavior~=tooltip_target]', controller)
        dayTarget = $('[data-behavior~=tooltip_day]', tooltipTarget)
        countTarget = $('[data-behavior~=tooltip_count]', tooltipTarget)

        tooltipTarget.removeClass('hide')
        dayTarget.text(bar.dataset.day)
        countTarget.text(bar.dataset.count)

        topOffset = tooltipTarget.prop("offsetHeight") + 4

        tooltipTarget.css
          top: "#{-topOffset}px"
          right: 'auto'
          left: 'auto'

        if bar.offsetLeft < parentWidth / 2
          tooltipTarget.removeClass("right")
          tooltipTarget.css
            left: "#{bar.offsetLeft - 14}px"
        else
          tooltipTarget.addClass("right")
          tooltipTarget.css
            right: "#{parentWidth - bar.offsetLeft - 18}px"

    sharePopup: ->
      $(document).on 'click', '[data-behavior~=share_popup]', (event) ->
        url = $(@).attr('href')
        feedbin.sharePopup(url)
        event.preventDefault()
        event.stopPropagation()

    navigatorShare: ->
      $(document).on 'click', '[data-behavior~=navigator_share]', (event) ->
        data =
          title: feedbin.selectedEntryData.title,
          url: feedbin.selectedEntryData.url,

        selection = feedbin.getSelectedText()
        if selection != ""
          data.text = selection

        navigator.share(data).catch (error) ->
          console.log error

        event.preventDefault()
        event.stopPropagation()

    copy: ->
      $(document).on 'click', '[data-behavior~=copy]', (event) ->
        button = $(@)
        input = button.siblings('input')
        input.focus()
        if input.length > 0
          input.select()
          try
            document.execCommand('copy');
          catch error
            if 'console' of window
              console.log error
        event.preventDefault()


$.each feedbin.preInit, (i, item) ->
  item()

jQuery ->
  $.each feedbin.init, (i, item) ->
    try
      item()
    catch error
      if 'console' of window
        console.log error
