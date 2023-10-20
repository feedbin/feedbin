import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="payments"
export default class extends Controller {
  static values = {
    url: String,
    checkoutId: String,
    stripePublicKey: String
  }

  connect(event) {
    const stripe = Stripe(this.stripePublicKeyValue);

    const request = window.$.post(this.urlValue)

    request.done((response) => {
      const { clientSecret } = response
      console.log(stripe);

      const checkout = stripe.initEmbeddedCheckout({
        clientSecret,
      })
      .then((x) => {
        // // Mount Checkout
        x.mount(`#${this.checkoutIdValue}`);
        console.log(`#${this.checkoutIdValue}`);
      })
    })
  }
}
