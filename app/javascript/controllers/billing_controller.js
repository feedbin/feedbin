import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="billing"
export default class extends Controller {
  static targets = ["paymentElement", "error", "submit", "planInput"]
  static values = {
    publishableKey: String,
    mode: String,
    amount: Number,
    currency: String,
    endpoint: String,
    returnUrl: String,
    defaultPlan: Number
  }

  async connect() {
    this.stripe = Stripe(this.publishableKeyValue)
    this.elements = this.stripe.elements({
      mode: this.modeValue,
      currency: this.currencyValue,
      amount: this.amountValue > 0 ? this.amountValue : undefined,
      appearance: this.appearance()
    })
    this.paymentElement = this.elements.create("payment")
    this.paymentElement.mount(this.paymentElementTarget)
  }

  planChanged(event) {
    const amount = parseInt(event.target.dataset.amount, 10)
    if (amount > 0) {
      this.elements.update({ amount })
    }
  }

  async submit(event) {
    event.preventDefault()
    this.setBusy(true)

    const { error: submitError } = await this.elements.submit()
    if (submitError) return this.fail(submitError.message)

    const { error: tokenError, confirmationToken } =
      await this.stripe.createConfirmationToken({ elements: this.elements })
    if (tokenError) return this.fail(tokenError.message)

    const payload = { confirmation_token: confirmationToken.id }
    if (this.hasPlanInputTarget) payload.plan_id = this.selectedPlanId()

    const response = await fetch(this.endpointValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content,
        "Accept": "application/json"
      },
      body: JSON.stringify(payload)
    })
    const data = await response.json()

    if (!response.ok) return this.fail(data.error || "Payment failed.")

    if (data.requires_action && data.client_secret) {
      const { error } = await this.stripe.handleNextAction({ clientSecret: data.client_secret })
      if (error) return this.fail(error.message)
    }

    window.location = this.returnUrlValue
  }

  selectedPlanId() {
    const checked = this.planInputTargets.find((input) => input.checked)
    return checked ? checked.value : this.defaultPlanValue
  }

  appearance() {
    const dark = ["dusk", "midnight"].includes(window.feedbin?.theme) || window.feedbin?.darkMode?.()
    return { theme: dark ? "night" : "stripe" }
  }

  setBusy(busy) {
    if (this.hasSubmitTarget) this.submitTarget.disabled = busy
  }

  fail(message) {
    this.setBusy(false)
    if (this.hasErrorTarget) {
      this.errorTarget.textContent = message
      this.errorTarget.classList.remove("hidden")
    }
  }
}
