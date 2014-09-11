window.feedbin ?= {}

jQuery ->
  new feedbin.CountsBehavior()

class feedbin.CountsBehavior
  constructor: ->
    $(document).on('click', '[data-behavior~=change_view_mode]', @changeViewMode)
    $(document).on('click', '[data-behavior~=show_entry_content]', @showEntryContent)
    $(document).on('ajax:beforeSend', '[data-behavior~=toggle_read]', @toggleRead)
    $(document).on('ajax:beforeSend', '[data-behavior~=toggle_starred]', @toggleStarred)
    @applyCounts()

  changeViewMode: (event) =>
    element = $(event.currentTarget)
    $('[data-behavior~=change_view_mode]').removeClass('selected')
    element.addClass('selected')

    feedbin.data.viewMode = element.data('view-mode')
    if feedbin.data.viewMode == 'view_all'
      feedbin.hideQueue = [];

    $('body').removeClass('view_all view_unread view_starred');
    $('body').addClass(feedbin.data.viewMode);
    @applyCounts()

    if feedbin.openFirstItem
      $('[data-behavior~=feeds_target] li:visible').first().find('a')[0].click();
      feedbin.openFirstItem = false;

  showEntryContent: (event) =>
    @applyStarred()
    clearTimeout feedbin.recentlyReadTimer
    container = $(event.currentTarget)
    entryInfo = $(container).data('entry-info')
    if !entryInfo.read
      $.post $(container).data('mark-as-read-path')
      feedbin.recentlyReadTimer = setTimeout ( ->
        $.post $(container).data('recently-read-path')
      ), 10000
      feedbin.Counts.get().removeEntry(entryInfo.id, entryInfo.feed_id, 'unread')
      @mark(entryInfo, 'read')

  toggleRead: (event, xhr) =>
    entryInfo = $('[data-behavior~=selected_entry_data]').data('entry-info')
    if entryInfo.read
      feedbin.Counts.get().addEntry(entryInfo.id, entryInfo.feed_id, entryInfo.published, 'unread')
      @unmark(entryInfo, 'read')
    else
      feedbin.Counts.get().removeEntry(entryInfo.id, entryInfo.feed_id, 'unread')
      @mark(entryInfo, 'read')

  mark: (entryInfo, property) ->
    @applyCounts()
    entryInfo[property] = true
    $("[data-entry-id=#{entryInfo.id}]").addClass(property)
    $("[data-entry-id=#{entryInfo.id}][data-behavior~=entry_info]").data('entry-info', entryInfo)

  unmark: (entryInfo, property) ->
    @applyCounts()
    entryInfo[property] = false
    $("[data-entry-id=#{entryInfo.id}]").removeClass(property)
    $("[data-entry-id=#{entryInfo.id}][data-behavior~=entry_info]").data('entry-info', entryInfo)

  applyCounts: ->
    $('[data-behavior~=needs_count]').each (index, element) =>
      group = $(element).data('count-group')
      groupId = $(element).data('count-group-id')

      collection = 'unread'
      if feedbin.data.viewMode == 'view_starred'
        collection = 'starred'

      counts = feedbin.Counts.get().counts[collection][group]

      count = 0
      if groupId
        if (groupId of counts)
          count = counts[groupId].length
          $(element).text(count)
        if (count == 0)
          $(element).parents('li').first().addClass('zero-count')
        else
          $(element).parents('li').first().removeClass('zero-count')
      else
        count = counts.length
        $(element).text(count)
        if (count == 0)
          $(element).addClass('hide')
        else
          $(element).removeClass('hide')

  toggleStarred: (event, xhr) =>
    entryInfo = $('[data-behavior~=selected_entry_data]').data('entry-info')
    if entryInfo.starred
      feedbin.Counts.get().removeEntry(entryInfo.id, entryInfo.feed_id, 'starred')
      @unmark(entryInfo, 'starred')
    else
      feedbin.Counts.get().addEntry(entryInfo.id, entryInfo.feed_id, entryInfo.published, 'starred')
      @mark(entryInfo, 'starred')

  applyStarred: ->
    entryInfo = $('[data-behavior~=selected_entry_data]').data('entry-info')
    if entryInfo
      starred = feedbin.Counts.get().counts.starred.all
      if _.contains(starred, entryInfo.id)
        @mark(entryInfo, 'starred')
