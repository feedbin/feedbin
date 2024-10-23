import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["input", "filterOption"];

  updateFilter(event) {
    let currentValue = this.inputTarget.value;
    const allFilters = this.filterOptionTargets.map((option) => option.dataset.inputFilterFilterParam);

    allFilters.forEach((filter) => {
      currentValue = currentValue.replace(filter, "");
    });

    let parts = [currentValue, event.params.filter].map((part) => part.trim()).filter((part) => part !== "")

    this.inputTarget.value = parts.join(" ");
  }
}
