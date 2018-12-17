window.feedbin ?= {}

$.extend feedbin,

  nowPlayingdata: {}
  forcePlay: false

  hasDuration: ->
    if isNaN(window.player.duration) || window.player.duration == 0
      false
    else
      true

  loadProgress: (entryId) ->
    if (entryId of feedbin.data.progress)
      feedbin.data.progress[entryId]
    else
      false

  initPlayer: (play = true) ->
    $('body').removeClass('audio-panel-minimized')
    $('body').removeClass('audio-panel-maximized')
    size = feedbin.data.audio_panel_size || "minimized"
    $('body').addClass("audio-panel-#{size}")

    window.player = new MediaElementPlayer 'audio_player',
      features: ['progress']
      classPrefix: 'mejs_empty__'
      defaultAudioWidth: 'auto'
      defaultAudioHeight: '5px'
      success: (mediaElement, domObject) ->
        feedbin.nowPlayingData = $(domObject).data()

        mediaElement.addEventListener 'timeupdate', (e) ->
          if feedbin.hasDuration()
            feedbin.data.progress[feedbin.nowPlayingData.entryId] =
              progress: window.player.currentTime
              duration: window.player.duration
          feedbin.timeRemaining(feedbin.nowPlayingData.entryId)

        mediaElement.addEventListener 'seeked', _.throttle(feedbin.updateProgress, 1000, {leading: false})
        mediaElement.addEventListener 'timeupdate', _.throttle(feedbin.updateProgress, 5000, {leading: false})
        mediaElement.addEventListener 'playing', feedbin.playState
        mediaElement.addEventListener 'pause', feedbin.playState
        mediaElement.addEventListener 'loadedmetadata', feedbin.loadedmetadata
        if play
          feedbin.play()
          mediaElement.play()
        else
          feedbin.timeRemaining(feedbin.nowPlayingData.entryId)

  loadedmetadata: ->
    if progress = feedbin.loadProgress(feedbin.nowPlayingData.entryId)
      window.player.setCurrentTime(progress.progress)

  updateProgress: ->
    if feedbin.hasDuration()
      form = $("[data-behavior~=audio_target] [data-behavior~=audio_progress_form_#{feedbin.nowPlayingData.entryId}]")
      if form.length > 0
        field = form.find('#recently_played_entry_progress').val(window.player.currentTime)
        field = form.find('#recently_played_entry_duration').val(window.player.duration)
        form.submit()

  play: ->
    feedbin.forcePlay = true
    buttons = $("[data-behavior~=audio_play_#{feedbin.nowPlayingData.entryId}]")
    buttons.addClass('playing')
    buttons.removeClass('paused')

  togglePlay: ->
    if window.player.paused
      window.player.play()
    else
      window.player.pause()

  setDuration: (entryId, duration) ->
    durationElement = $("[data-behavior~=audio_duration_#{entryId}]")
    if $.trim(durationElement.text()) == ''
      minutes = Math.floor(duration / 60);
      durationElement.text("#{minutes} minutes")

  timeRemaining: (entryId) ->
    if progress = feedbin.loadProgress(entryId)
      durationElement = $("[data-behavior~=audio_duration_#{entryId}]")
      left = progress.duration - progress.progress
      minutes = Math.floor(left / 60);
      if minutes <= 1
        message = "1 minute left"
      else
        message = "#{minutes} minutes left"
      durationElement.text(message)

  playState: ->
    if typeof(window.player) != "undefined"
      if feedbin.hasDuration()
        feedbin.setDuration(feedbin.nowPlayingData.entryId, window.player.duration)

      if !feedbin.forcePlay
        play = $("[data-behavior~=audio_play_#{feedbin.nowPlayingData.entryId}]")
        if window.player.paused
          play.addClass('paused')
          play.removeClass('playing')
        else
          play.addClass('playing')
          play.removeClass('paused')

      feedbin.forcePlay = false

  audioJump: (time) ->
    window.player.setCurrentTime(window.player.currentTime + time)


$.extend feedbin,

  audioInit:

    launch: ->
      $(document).on 'click', '[data-behavior~=audio_launch_player]', (event) ->
        init = ->
          $('body').addClass("animate-panel")
          source = $("[data-behavior~=audio_markup]")
          target = $("[data-behavior~=audio_target]")
          target.html(source.html())

          $("[data-behavior~=audio_target] [data-behavior~=now_playing_form]").submit()
          feedbin.initPlayer()

        if typeof(window.player) == "undefined"
          init()
        else
          size = feedbin.data.audio_panel_size || "minimized"
          $('body').addClass("audio-panel-#{size}")
          if feedbin.nowPlayingData.entryId == $(@).data('entry-id')
            feedbin.togglePlay()
          else
            init()

    togglePanel: ->
      $(document).on 'click', '[data-behavior~=toggle_audio_panel]', (event) ->
        if $(event.target).has('[data-behavior~=toggle_audio_panel]')
          if $('body').hasClass('audio-panel-minimized')
            $('body').removeClass('audio-panel-minimized')
            $('body').addClass('audio-panel-maximized')
            feedbin.data.audio_panel_size = "maximized"
          else
            $('body').removeClass('audio-panel-maximized')
            $('body').addClass('audio-panel-minimized')
            feedbin.data.audio_panel_size = "minimized"
          form = $("[data-behavior~=audio_target] [data-behavior~=audio_panel_size]")
          form.find('#audio_panel_size').val(feedbin.data.audio_panel_size)
          form.submit()

    skipForward: ->
      $(document).on 'click', '[data-behavior~=audio_skip_forward]', (event) ->
        feedbin.audioJump(30)
        event.stopPropagation()

    skipBackward: ->
      $(document).on 'click', '[data-behavior~=audio_skip_backward]', (event) ->
        feedbin.audioJump(-30)
        event.stopPropagation()

    playPause: ->
      $(document).on 'click', '[data-behavior~=audio_play]', (event) ->
        feedbin.togglePlay()
        event.stopPropagation()

    close: ->
      $(document).on 'click', '.audio-progress', (event) ->
        event.stopPropagation()

      $(document).on 'click', '[data-behavior~=close_audio]', (event) ->
        $("[data-behavior~=audio_target] [data-behavior~=remove_now_playing]").submit()

        window.player.pause()
        $('body').removeClass('audio-panel-minimized')
        $('body').removeClass('audio-panel-maximized')
        event.stopPropagation()

jQuery ->
  $.each feedbin.audioInit, (i, item) ->
    item()
