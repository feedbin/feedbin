import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="billing"
export default class extends Controller {
  static targets = ["paymentElement", "error", "submit", "planInput", "planHelp"]
  static values = {
    publishableKey: String,
    mode: String,
    amount: Number,
    currency: String,
    endpoint: String,
    returnUrl: String,
    defaultPlan: Number,
    mounted: { type: Boolean, default: false }
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
    // Sets data-billing-mounted-value="true"; markup reveals the charge
    // description purely via a Tailwind group-data variant (no classList here).
    this.paymentElement.on("ready", () => { this.mountedValue = true })
    this.paymentElement.mount(this.paymentElementTarget)
  }

  planChanged(event) {
    const amount = parseInt(event.target.dataset.amount, 10)
    if (amount > 0) {
      this.elements.update({ amount })
    }
    this.planHelpTargets.forEach((el) => {
      el.classList.toggle("hidden", el.dataset.planId !== event.target.value)
    })
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

    const data = await this.post(payload)
    if (data === null) return

    if (data.requires_action && data.client_secret) {
      const { error } = await this.stripe.handleNextAction({ clientSecret: data.client_secret })
      if (error) return this.fail(error.message)

      const finalizePayload = { intent_id: data.client_secret.split("_secret_")[0] }
      if (this.hasPlanInputTarget) finalizePayload.plan_id = this.selectedPlanId()
      const finalizeData = await this.post(finalizePayload)
      if (finalizeData === null) return
    }

    window.location = this.returnUrlValue
  }

  async post(payload) {
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
    if (!response.ok) {
      this.fail(data.error || "Payment failed.")
      return null
    }
    return data
  }

  selectedPlanId() {
    const checked = this.planInputTargets.find((input) => input.checked)
    return checked ? checked.value : this.defaultPlanValue
  }

  // Match the Payment Element to the site by resolving its theme CSS custom
  // properties to concrete values. The Element renders in a cross-origin iframe
  // so it can't read page CSS, and colorPrimary/Background/Text/Danger reject
  // var()/rgba() — so we resolve each --color-* (which the site swaps per theme)
  // off a hidden probe and feed hex/rgb values in.
  appearance() {
    const dark = ["dusk", "midnight"].includes(window.feedbin?.theme) || window.feedbin?.darkMode?.()

    const probe = document.createElement("span")
    probe.style.display = "none"
    this.element.appendChild(probe)
    const compute = (cssVar) => {
      probe.style.color = `var(${cssVar})`
      return getComputedStyle(probe).color
    }
    const hex = (cssVar) => {
      const [r, g, b] = compute(cssVar).match(/\d+(\.\d+)?/g).map(Number)
      return "#" + [r, g, b].map((n) => Math.round(n).toString(16).padStart(2, "0")).join("")
    }

    const base = hex("--color-base")
    const text = hex("--color-600")
    const strong = hex("--color-700")
    const secondary = hex("--color-500")
    const border = hex("--color-400")
    const primary = hex("--color-blue-600")
    const danger = hex("--color-red-600")
    const shadow = compute("--color-shadow-100")
    probe.remove()

    return {
      theme: dark ? "night" : "stripe",
      variables: {
        fontFamily: "-apple-system, BlinkMacSystemFont, 'Helvetica Neue', Helvetica, Arial, sans-serif",
        fontSizeBase: "14px",
        borderRadius: "6px",
        colorBackground: base,
        colorText: text,
        colorTextSecondary: secondary,
        colorTextPlaceholder: secondary,
        colorPrimary: primary,
        colorDanger: danger
      },
      rules: {
        ".Input": {
          border: `1px solid ${border}`,
          boxShadow: `0px 1px 1px 0px ${shadow}`,
          padding: "11px 8px"
        },
        ".Input:focus": {
          color: strong,
          border: `1px solid ${primary}`,
          boxShadow: `0 0 0 1px ${primary}`
        },
        ".Input--invalid": {
          border: `1px solid ${danger}`,
          boxShadow: `0 0 0 1px ${danger}`
        },
        ".Label": {
          color: text,
          fontWeight: "500"
        },
        ".Tab": {
          border: `1px solid ${border}`,
          boxShadow: `0px 1px 1px 0px ${shadow}`
        },
        ".Tab:hover": {
          color: strong
        },
        ".Tab--selected": {
          color: strong,
          borderColor: primary,
          boxShadow: `0 0 0 1px ${primary}`
        },
        ".Error": {
          color: danger
        }
      }
    }
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
