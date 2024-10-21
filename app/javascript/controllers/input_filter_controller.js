import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["input", "filterOption"];

  updateFilter(event) {
    let currentValue = this.inputTarget.value;
    const allFilters = this.filterOptionTargets.map((option) => {option.dataset.inputFilterFilterParam});

    allFilters.forEach((filter) => {
      currentValue = currentValue.replace(` ${filter}`, "");
    });

    this.inputTarget.value = `${currentValue} ${event.params.filter}`;
  }
}
