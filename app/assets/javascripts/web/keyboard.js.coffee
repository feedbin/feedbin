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

    $(document).on 'click', '.entry-content', (event) =>
      unless $(event.originalEvent.target).is('a') || $(event.originalEvent.target).parents('a').length > 0
        @selectColumn('entry-content')
      return

    $(document).on 'click', '[data-behavior~=open_next_entry]', (event) =>
      @selectColumn('entries')
      @setEnvironment()
      @item = @next
      @selectItem()
      event.preventDefault()

    $(document).on 'click', '[data-behavior~=open_previous_entry]', (event) =>
      @selectColumn('entries')
      @setEnvironment()
      @item = @previous
      @selectItem()
      event.preventDefault()

  navigateShareMenu: (combo) ->
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

  navigateFeedbin: (combo) ->
    @setEnvironment()
    if 'pagedown' == combo || 'shift+j' == combo
      if 'entry-content' == @selectedColumnName() || feedbin.isFullScreen()
        @scrollContent(@contentHeight() - 100, 'down')
    else if 'pageup' == combo || 'shift+k' == combo
      if 'entry-content' == @selectedColumnName() || feedbin.isFullScreen()
        @scrollContent(@contentHeight() - 100, 'up')
    else if 'down' == combo || 'j' == combo
      if 'entry-content' == @selectedColumnName() || feedbin.isFullScreen()
        @scrollContent(30, 'down')
      else
        @item = @next
        @selectItem()
    else if 'up' == combo || 'k' == combo
      if 'entry-content' == @selectedColumnName() || feedbin.isFullScreen()
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

  navigateEntryContent: (combo) ->
    @selectColumn('entries')
    @setEnvironment()
    if 'pagedown' == combo
      @scrollContent(@contentHeight() - 100, 'down')
    else if 'pageup' == combo
      @scrollContent(@contentHeight() - 100, 'up')
    else if 'down' == combo
      @scrollContent(30, 'down')
    else if 'up' == combo
      @scrollContent(30, 'up')
    else if 'j' == combo
      @item = @next
      @selectItem()
    else if 'k' == combo
      @item = @previous
      @selectItem()

  bindKeys: ->
    if $('body.app').length == 0
      return

    Mousetrap.bind ['pageup', 'pagedown', 'up', 'down', 'left', 'right', 'j', 'k', 'h', 'l', 'shift+j', 'shift+k'], (event, combo) =>
      if feedbin.shareOpen()
        @navigateShareMenu(combo)
      else if feedbin.isFullScreen()
        @navigateEntryContent(combo)
      else
        @navigateFeedbin(combo)
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
      $('[data-behavior~=toggle_extract]').submit()
      event.preventDefault()

    # Go to unread
    Mousetrap.bind ['g 1', 'g u'], (event, combo) =>
      $('body').removeClass('full-screen')
      $('[data-behavior~=change_view_mode][data-view-mode=view_unread]').click()
      $('.dropdown-wrap').removeClass('open')
      event.preventDefault()

    # Go to starred
    Mousetrap.bind ['g 2', 'g s'], (event, combo) =>
      $('body').removeClass('full-screen')
      $('[data-behavior~=change_view_mode][data-view-mode=view_starred]').click()
      $('.dropdown-wrap').removeClass('open')
      event.preventDefault()

    # Go to all
    Mousetrap.bind ['g 3', 'g a'], (event, combo) =>
      $('body').removeClass('full-screen')
      $('[data-behavior~=change_view_mode][data-view-mode=view_all]').click()
      $('.dropdown-wrap').removeClass('open')
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
      $('body').removeClass('full-screen')
      $('[data-behavior~=show_subscribe]').click()
      event.preventDefault()

    # Show Keyboard shortcuts
    Mousetrap.bind '?', (event, combo) =>
      feedbin.showModal("help")
      event.preventDefault()

    # Focus search
    Mousetrap.bind '/', (event, combo) =>
      $('body').removeClass('full-screen')
      feedbin.showSearch()
      event.preventDefault()

    # Open original article
    Mousetrap.bind 'v', (event, combo) =>
      content = $('#source_link')[0].click()
      event.preventDefault()

    # Open original article
    Mousetrap.bind 'V', (event, combo) =>
      href = $('#source_link').attr('href')
      if href
        feedbin.openLinkInBackground(href)
      event.preventDefault()

    # Expand tag
    Mousetrap.bind 'e', (event, combo) =>
      content = $('[data-behavior~=feeds_target]').find('.selected').find('[data-behavior~=toggle_drawer]').submit()
      event.preventDefault()

    # Edit
    Mousetrap.bind 'shift+e', (event, combo) =>
      $('[data-behavior~=feed_settings]').click()
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

    # sharing hotkeys
    Mousetrap.bind ['1', '2', '3', '4', '5', '6', '7', '8', '9'], (event, combo) =>
      shareMenu = $('[data-behavior~=share_options]')
      if shareMenu.length > 0
        shareIndex = combo - 1
        $('li', shareMenu).eq(shareIndex).find('a')[0].click()

    # Full Screen
    Mousetrap.bind 'F', (event, combo) =>
      if $('[data-behavior~=entry_content_target]').html().length > 0
        feedbin.toggleFullScreen()
      event.preventDefault()

    Mousetrap.bind 'enter', (event, combo) =>
      if feedbin.shareOpen()
        dropdown = $('.dropdown-wrap')
        $('li.selected a', dropdown)[0].click()
        event.preventDefault()

    # Unfocus field,
    Mousetrap.bindGlobal 'escape', (event, combo) =>
      feedbin.hideSubscribe()
      feedbin.hideSearch()
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

    Mousetrap.bind 'C', (event, combo) =>
      link = $('#source_link_field')
      if link.length > 0
        link.select()
        try
          document.execCommand('copy');
          link.blur()
        catch error
          if 'console' of window
            console.log error
      event.preventDefault()

    $(window).on 'keydown', (event) =>
      keys = {
        UIKeyInputUpArrow: "up",
        UIKeyInputDownArrow: "down",
        UIKeyInputLeftArrow: "left",
        UIKeyInputRightArrow: "right"
      }

      if keys[event.key]
        if feedbin.shareOpen()
          @navigateShareMenu(keys[event.key])
        else if feedbin.isFullScreen()
          @navigateEntryContent(keys[event.key])
        else
          @navigateFeedbin(keys[event.key])
        event.preventDefault()

  setEnvironment: ->
    @selected = @selectedItem()
    @columnOffsetTop = @selectedColumn.offset().top
    @next = @nextItem()
    @previous = @previousItem()
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
        selectedItem = $('[data-behavior~=feeds_target] li:visible').eq(0)

    selectedItem

  previousItem: ->
    if @selectedColumnName() == 'feeds'
      @drawer = @selected.prevAll().not(":hidden, .source-section").first().find('.drawer')
      if @inDrawer()
        prev = @selected.prevAll().not(":hidden, .source-section").first();
        if prev.length == 0
          prev = @selected.parents('li[data-tag-id]');
      else if @hasDrawer()
        prev = $('ul li', @drawer).not(":hidden, .source-section").last();
      else
        prev = @selected.prevAll().not(":hidden, .source-section").first();
    else
      prev = @selectedItem().prev()
    prev

  nextItem: ->
    if @selectedColumnName() == 'feeds'
      @drawer = $('.drawer', @selectedItem())
      if @inDrawer()
        next = @selected.nextAll().not(":hidden, .source-section").first();
        if next.length == 0
          next = @selected.parents('li[data-tag-id]').nextAll().not(":hidden, .source-section").first();
      else if @hasDrawer()
        next = $('ul li', @drawer).not(":hidden, .source-section").first();
      else
        next = @selected.nextAll().not(":hidden, .source-section").first();
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
    @item = @columns['feeds'].find('.selected').nextAll('li').find('.count').not(':hidden, .source-section').first().parents('li')
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
    @entryScrollHeight() - $('.entry-content').prop('scrollTop') > 2

  scrollContent: (interval, direction) ->
    if 'down' == direction
      newPosition = $('.entry-content').prop('scrollTop') + interval
    else if 'up' == direction
      newPosition = $('.entry-content').prop('scrollTop') - interval
    if newPosition > @entryScrollHeight()
      newPosition = @entryScrollHeight()
    $('.entry-content').prop 'scrollTop', newPosition

  entryScrollHeight: ->
    $('.entry-content').prop('scrollHeight') - $('.entry-content').prop('offsetHeight') - @nextEntryPreviewHeight()

  contentHeight: ->
    $('.entry-content').prop('clientHeight')

  nextEntryPreviewHeight: ->
    container = $('.next-entry-preview')
    if container.is(":visible") then container.height() else 0
