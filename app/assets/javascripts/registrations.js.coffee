window.feedbin ?= {}

jQuery ->
  new feedbin.Registration()

class feedbin.Registration
  constructor: ->
    Stripe.setPublishableKey($('meta[name="stripe-key"]').attr('content'))
    $('#card_number').payment('formatCardNumber');
    $('#card_expiration').payment('formatCardExpiry');
    $('#card_code').payment('formatCardCVC');

    $(document).on 'change', '#card_month, #card_year', (event) ->
      $('#card_expiration').val("#{$('#card_month').val()} / #{$('#card_year').val()}")

    $(document).on 'submit', '[data-behavior~=credit_card_form]', (event) =>
      $('[data-behavior~=stripe_error]').addClass('hide')
      $('input[type=submit]').attr('disabled', true)
      if $('#card_number').length
        @processCard()
        event.preventDefault()
      else
        true

  processCard: ->
    expiration = $('#card_expiration').payment('cardExpiryVal')
    card =
      number: $('#card_number').val()
      cvc: $('#card_code').val()
      expMonth: expiration.month
      expYear: expiration.year
    Stripe.createToken(card, @handleStripeResponse)

  handleStripeResponse: (status, response) ->
    if status == 200
      $('[data-behavior~=stripe_token]').val(response.id)
      $('[data-behavior~=credit_card_form]')[0].submit()
    else
      $('[data-behavior~=stripe_error]').removeClass('hide')
      $('[data-behavior~=stripe_error]').text(response.error.message)
      $('input[type=submit]').removeAttr('disabled')
