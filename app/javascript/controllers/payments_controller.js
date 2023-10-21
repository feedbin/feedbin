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

    const elements = stripe.elements({
      mode: "subscription",
      amount: 0,
      currency: "usd",
    });

    const paymentElement = elements.create("payment", {
      layout: {
        type: "accordion"
      }
    });
    paymentElement.mount(`#${this.checkoutIdValue}`);
  }
}
