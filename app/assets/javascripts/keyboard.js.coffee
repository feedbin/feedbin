window.feedbin ?= {}

jQuery ->
  new feedbin.Keyboard()

class feedbin.Keyboard
  constructor: ->
    @columns =
      feeds: $('.feeds')
      entries: $('.entries')

    @selectColumn('feeds')

    # The right key should be locked until entries finishes loading
    @rightLock = false
    @waitingForEntries = false

    @bindKeys()
    @bindEvents()

  bindEvents: ->
    $(document).on 'click', '[data-behavior~=open_item]',  (event) =>
      parent = $(event.currentTarget).parents('div')
      if parent.hasClass('entries')
        @selectColumn('entries')
      else if parent.hasClass('feeds')
        @selectColumn('feeds')
      return

    $(document).on 'ajax:complete', '[data-behavior~=show_entries]', =>
      @rightLock = false
      if @waitingForEntries
        @openFirstItem()
        @waitingForEntries = false
      return

  bindKeys: ->
    Mousetrap.bind ['up', 'down', 'left', 'right', 'j', 'k', 'h', 'l'], (event, combo) =>

      # If share menu is showing intercept up down
      dropdown = $('[data-behavior~=toggle_share_menu]').parents('.dropdown-wrap')
      if dropdown.hasClass('open')
        nextShare = false
        selectedShare = $('li.selected', dropdown)
        if 'down' == combo
          nextShare = selectedShare.next()
          if nextShare.length == 0
            nextShare = $('li:first-child', dropdown)
        else if 'up' == combo
          nextShare = selectedShare.prev()
          if nextShare.length == 0
            nextShare = $('li:last-child', dropdown)

        if nextShare
          $('li.selected', dropdown).removeClass('selected')
          nextShare.addClass('selected')

        event.preventDefault()
        return null

      @setEnvironment()

      if 'down' == combo || 'j' == combo
        if 'entry-content' == @selectedColumnName()
          @scrollContent(30, 'down')
        else
          @item = @next
          @selectItem()
      else if 'up' == combo || 'k' == combo
        if 'entry-content' == @selectedColumnName()
          @scrollContent(30, 'up')
        else
          @item = @previous
          @selectItem()
      else if 'right' == combo || 'l' == combo
        if 'feeds' == @selectedColumnName()
          if @rightLock
            @waitingForEntries = true
          else
            @openFirstItem()
        else if 'entries' == @selectedColumnName()
          @selectColumn('entry-content')

      else if 'left' == combo || 'h' == combo
        if 'entry-content' == @selectedColumnName()
          @selectColumn('entries')
        else if 'entries' == @selectedColumnName()
          if @columns['feeds'].find('.selected').length > 0
            @selectColumn('feeds')
          else
            $("[data-feed-id=#{feedbin.feedCandidates[0]}]").find('[data-behavior~=open_item]').click()
            feedbin.feedCandidates = []
      event.preventDefault()

    Mousetrap.bind ['space'], (event, combo) =>
      @setEnvironment()
      if @hasEntryContent()
        @selectColumn('entry-content')
        interval = $('.entry-content').height() - 20
        @scrollContent(interval, 'down')
      else if @hasUnreadEntries()
        @selectNextUnreadEntry()
      else if @hasUnreadFeeds()
        @selectNextUnreadFeed()
      event.preventDefault()

    # Star
    Mousetrap.bind 's', (event, combo) =>
      $('[data-behavior~=toggle_starred]').submit()
      event.preventDefault()

    # Read/Unread
    Mousetrap.bind 'm', (event, combo) =>
      $('[data-behavior~=toggle_read]').submit()
      event.preventDefault()

    # Content View
    Mousetrap.bind 'c', (event, combo) =>
      $('[data-behavior~=toggle_content_view]').submit()
      event.preventDefault()

    # Go to all
    Mousetrap.bind 'g a', (event, combo) =>
      $('[data-behavior~=all_unread] [data-behavior~=open_item]').click()
      event.preventDefault()

    # Go to starred
    Mousetrap.bind 'g s', (event, combo) =>
      $('[data-behavior~=starred] [data-behavior~=open_item]').click()
      event.preventDefault()

    # Mark as read
    Mousetrap.bind 'shift+a', (event, combo) =>
      currentEntry = @columns['entries'].find('.selected')
      @alternateEntryCandidates = []
      @alternateEntryCandidates.push currentEntry.next() if currentEntry.next().length
      @alternateEntryCandidates.push currentEntry.prev() if currentEntry.prev().length

      $('[data-behavior~=mark_all_as_read]').first().click()
      event.preventDefault()

    # Add subscription
    Mousetrap.bind 'a', (event, combo) =>
      $('[data-behavior~=show_subscribe]').click()
      event.preventDefault()

    # Focus search
    Mousetrap.bind '/', (event, combo) =>
      $('[name="query"]').focus()
      event.preventDefault()

    # Show Keyboard shortcuts
    Mousetrap.bind '?', (event, combo) =>
      if feedbin.modalShowing == true
        $('.modal').modal('hide')
        feedbin.modalShowing = false
      else
        content = $('[data-behavior~=keyboard_shortcuts]').html()
        feedbin.modalBox(content);
      event.preventDefault()

    # Open original article
    Mousetrap.bind 'v', (event, combo) =>
      content = $('.entry-header').find('a')[0].click()
      event.preventDefault()

    # Open original article
    Mousetrap.bind 'V', (event, combo) =>
      href = $('.entry-header').find('a').attr('href')
      if href
        feedbin.openLinkInBackground(href)
      event.preventDefault()

    # Expand tag
    Mousetrap.bind 'e', (event, combo) =>
      content = $('[data-behavior~=feeds_target]').find('.selected').find('[data-behavior~=toggle_drawer]').click()
      event.preventDefault()

    # refresh
    Mousetrap.bind 'r', (event, combo) =>
      feedbin.refresh()
      event.preventDefault()

    # share menu
    Mousetrap.bind 'f', (event, combo) =>
      shareButton = $("[data-behavior~=toggle_share_menu]")
      if shareButton.length > 0
        shareButton.click()
        event.preventDefault()

    Mousetrap.bind 'enter', (event, combo) =>
      if feedbin.shareOpen()
        dropdown = $('.dropdown-wrap')
        $('li.selected a', dropdown)[0].click()
        event.preventDefault()

    # Unfocus field,
    Mousetrap.bindGlobal 'escape', (event, combo) =>
      $('.feeds').removeClass('show-subscribe')
      if feedbin.modalShowing == true
        $('.modal').modal('hide')
        event.preventDefault()

      if $('[name="subscription[feeds][feed_url]"]').is(':focus')
        $('[name="subscription[feeds][feed_url]"]').blur()
        event.preventDefault()

      if $('[name=query]').is(':focus')
        $('[name=query]').blur()
        event.preventDefault()

      if feedbin.shareOpen()
        dropdown = $('.dropdown-wrap')
        dropdown.removeClass('open')
        event.preventDefault()

  setEnvironment: ->
    @columnOffsetTop = @selectedColumn.offset().top
    @next = @nextItem()
    @previous = @previousItem()
    @selected = @selectedItem()
    @containerHeight = @selectedColumn.outerHeight()
    @scrollTop = @selectedColumn.prop('scrollTop')

  clickItem: _.debounce( ->
    @item.find('[data-behavior~=open_item]:first').click()
  50)

  selectItem: ->
    if 'feeds' == @selectedColumnName()
      @rightLock = true
    if @item.length > 0
      @itemPosition = @getItemPosition()
      unless @itemInView()
        @scrollOne()
      @selected.removeClass('selected')
      @item.addClass('selected')
      @clickItem()
    else
      @item = @selected
      @clickItem()

  openFirstItem: ->
    @selectColumn('entries')
    selectedEntry = @columns['entries'].find('.selected')
    unless selectedEntry.length > 0
      @selectedColumn.find('li:first-child [data-behavior~=open_item]').click()

  selectedColumnName: ->
    if @selectedColumn.hasClass 'feeds'
      'feeds'
    else if @selectedColumn.hasClass 'entries'
      'entries'
    else if @selectedColumn.hasClass 'entry-content'
      'entry-content'

  selectColumn: (column) ->
    @selectedColumn = $(".#{column}")
    $("[data-behavior~=content_column]").removeClass('selected')
    $(".#{column}").closest("[data-behavior~=content_column]").addClass('selected')

  itemInView: ->
    try
      drawer = @item.find('.drawer').outerHeight()
    catch error
      drawer = 0
    @itemAboveView = @itemPosition.bottom < @item.outerHeight() - drawer
    @itemBelowView = @itemPosition.bottom > @containerHeight
    @itemAboveView && @itemBelowView

  selectedItem: ->
    selectedItem = @selectedColumn.find('.selected')
    if selectedItem.length == 0 && 'entry-content' != @selectedColumnName()

      possibilities =
        entries: @columns['entries'].find('.selected')
        feeds: @columns['feeds'].find('.selected')

      $.each possibilities, (column, item) =>
        if item.length
          @selectColumn(column)
          selectedItem = item
          return false

      unless selectedItem.length
        selectedItem = $('[data-behavior~=feeds_target] li:first-child')

    selectedItem

  previousItem: ->
    @drawer = @selectedItem().prev().find('.drawer')
    if @inDrawer()
      prev = @selectedItem().prev()
      if prev.length == 0
        prev = @selectedItem().parents('li[data-tag-id]')
    else if @hasDrawer()
      prev = $('ul li:last-child', @drawer)
    else
      prev = @selectedItem().prev()
    prev

  nextItem: ->
    @drawer = $('.drawer', @selectedItem())
    if @inDrawer()
      next = @selectedItem().next()
      if next.length == 0
        next = @selectedItem().parents('li[data-tag-id]').next()
    else if @hasDrawer()
      next = $('ul li:first-child', @drawer)
    else
      next = @selectedItem().next()
    next

  inDrawer: ->
    @selectedItem().parents('.drawer').length >= 1

  hasDrawer: ->
    @drawer.length >= 1 && @drawer.data('hidden') == false

  getItemPosition: ->
    try
      drawer = @item.find('.drawer').outerHeight()
    catch error
      drawer = 0
    bottom: (@item.offset().top - @columnOffsetTop) + @item.outerHeight() - drawer
    top: (@item.offset().top - @columnOffsetTop)

  scrollOne: ->
    if @itemAboveView
      @scrollColumn @scrollTop + @itemPosition.top
    else if @itemBelowView
      if @selectedColumnName() == 'entries'
        offset = 17 # above chrome's status bar
      else
        offset = 0
      @scrollColumn (@itemPosition.bottom + @scrollTop + offset) - @containerHeight
    else

  scrollColumn: (position) ->
    @selectedColumn.prop 'scrollTop', position

  # Space bar nav
  hasUnreadFeeds: ->
    @columns['feeds'].find('.selected').nextAll('li').find('.count').not('.hide').length

  selectNextUnreadFeed: ->
    @item = @columns['feeds'].find('.selected').nextAll('li').find('.count').not('.hide').first().parents('li')
    @selectItem()

  hasUnreadEntries: ->
    if 'feeds' == @selectedColumnName()
      @columns['entries'].find('li').not('.read').first().length
    else
      @columns['entries'].find('.selected').nextAll('li').not('.read').first().length

  selectNextUnreadEntry: ->
    if 'feeds' == @selectedColumnName()
      @selectColumn('entries')
      @item = @columns['entries'].find('li').not('.read').first()
    else
      @selectColumn('entries')
      @setEnvironment()
      @item = @columns['entries'].find('.selected').nextAll('li').not('.read').first()
    @selected = @item
    @selectItem()

  hasEntryContent: ->
    @entryScrollHeight() - $('.entry-content').prop('scrollTop') > 0

  scrollContent: (interval, direction) ->
    if 'down' == direction
      newPosition = $('.entry-content').prop('scrollTop') + interval
    else if 'up' == direction
      newPosition = $('.entry-content').prop('scrollTop') - interval
    if newPosition > @entryScrollHeight()
      newPosition = @entryScrollHeight()
    $('.entry-content').prop 'scrollTop', newPosition

  entryScrollHeight: ->
    $('.entry-content').prop('scrollHeight') - $('.entry-content').prop('offsetHeight')
