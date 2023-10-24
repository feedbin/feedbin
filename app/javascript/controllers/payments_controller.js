import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="payments"
export default class extends Controller {
  static targets = ["paymentContainer", "submitButton"]
  static outlets = [ "expandable-container" ]
  static values = {
    submitUrl: String,
    confirmationUrl: String,
    checkoutId: String,
    stripePublicKey: String,
    ready: Boolean,
    visible: Boolean
  }

  stripe = null
  elements = null

  connect(event) {



    this.stripe = Stripe(this.stripePublicKeyValue)

    this.elements = this.stripe.elements({
      mode: "subscription",
      amount: 0,
      currency: "usd",
      appearance: this.appearance(),
    })

    const paymentElement = this.elements.create("payment")

    paymentElement.on("ready", (event) => {
      this.readyValue = true
      this.expandableContainerOutlet.toggle()
    })

    paymentElement.mount(`#${this.checkoutIdValue}`)
  }

  async submit(event) {
    console.log(event)
    event.preventDefault()

    if (this.submitButtonTarget.disabled) {
      console.log("disabled")
      return
    }

    // Disable form submission while loading
    this.submitButtonTarget.disabled = true

    // Trigger form validation and wallet collection
    const {error: submitError} = await this.elements.submit()
    if (submitError) {
      this.handleError(submitError)
      return
    }

    let response

    try {
      response = await window.$.post(this.submitUrlValue)
      console.log(response);
    } catch (e) {
      this.handleError({message: "An unknown error occurred."})
      return
    }

    console.log(response);

    const {type, clientSecret} = response
    const confirmIntent = type === "setup" ? this.stripe.confirmSetup : this.stripe.confirmPayment

    const {error} = await confirmIntent({
      clientSecret,
      elements: this.elements,
      confirmParams: {
        return_url: this.confirmationUrlValue,
      },
    })

    if (error) {
      // This point is only reached if there"s an immediate error when confirming the Intent.
      // Show the error to your customer (for example, "payment details incomplete").
      this.handleError(error)
    } else {
      // Your customer is redirected to your `return_url`. For some payment
      // methods like iDEAL, your customer is redirected to an intermediate
      // site first to authorize the payment, then redirected to the `return_url`.
    }
  }

  handleError(error) {
    window.feedbin.showNotification(error.message, true)
    this.submitButtonTarget.disabled = false
  }

  appearance() {
    return {
      theme: "flat",
      variables: {
        fontSizeBase:         "16px",
        spacingGridRow:       "1rem",
        spacingUnit:          "3px",
        borderRadius:         "0.375rem",
        fontSizeSm:           "0.875rem",
        fontSize3Xs:          "0.875rem",
        colorPrimary:         window.getComputedStyle(document.body).getPropertyValue("--color-link"),
        colorText:            window.getComputedStyle(document.body).getPropertyValue("--color-600"),
        colorTextSecondary:   window.getComputedStyle(document.body).getPropertyValue("--color-500"),
        colorBackground:      window.getComputedStyle(document.body).getPropertyValue("--color-base"),
        colorDanger:          window.getComputedStyle(document.body).getPropertyValue("--color-red-600"),
        colorDanger:          window.getComputedStyle(document.body).getPropertyValue("--color-red-600"),
        colorDanger:          window.getComputedStyle(document.body).getPropertyValue("--color-red-600"),
        colorIconTab:         window.getComputedStyle(document.body).getPropertyValue("--color-500"),
        colorIconTabSelected: window.getComputedStyle(document.body).getPropertyValue("--color-700"),
      },
      rules: {
        ".Tab": {
          border: "1px solid transparent",
          borderColor: window.getComputedStyle(document.body).getPropertyValue("--border-color"),
          fontSize: "0.875rem",
          boxShadow: "none",
          marginBottom: "1rem",
        },
        ".Tab--selected": {
          color: window.getComputedStyle(document.body).getPropertyValue("--color-700"),
          borderColor: window.getComputedStyle(document.body).getPropertyValue("--color-blue-600"),
          boxShadow: `0px 0px 0px 1px ${window.getComputedStyle(document.body).getPropertyValue("--color-blue-600")}`,
          backgroundColor: window.getComputedStyle(document.body).getPropertyValue("--color-base"),
        },
        ".Tab--selected:hover": {
          color: window.getComputedStyle(document.body).getPropertyValue("--color-700"),
          boxShadow: `0px 0px 0px 1px ${window.getComputedStyle(document.body).getPropertyValue("--color-blue-600")}`,
        },
        ".Tab--selected:focus": {
          boxShadow: `0px 0px 0px 1px ${window.getComputedStyle(document.body).getPropertyValue("--color-blue-600")}`,
        },
        ".Input": {
          border: "1px solid transparent",
          borderColor: window.getComputedStyle(document.body).getPropertyValue("--border-color"),
          fontSize: "0.875rem",
          boxShadow: "none",
        },
        ".Input:focus": {
          color: window.getComputedStyle(document.body).getPropertyValue("--color-700"),
          borderColor: window.getComputedStyle(document.body).getPropertyValue("--color-blue-600"),
          boxShadow: `0px 0px 0px 1px ${window.getComputedStyle(document.body).getPropertyValue("--color-blue-600")}`
        },
        ".Label": {
          fontSize: "1rem",
          marginBottom: "0.5rem",
          lineHeight: "1.5rem",
        },
        ".Block": {
          border: "1px solid transparent",
          borderColor: window.getComputedStyle(document.body).getPropertyValue("--border-color"),
          backgroundColor: window.getComputedStyle(document.body).getPropertyValue("--color-base"),
          boxShadow: "none",
        },
        ".BlockDivider": {
          backgroundColor: window.getComputedStyle(document.body).getPropertyValue("--border-color"),
        },
      }
    }
  }
}
