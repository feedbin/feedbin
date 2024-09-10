import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static values = {
    section: String
  }

  connect() {
    this.lastScrollPosition = 0;
    this.cssClass = `hide-${this.sectionValue}-toolbar`
  }

  scroll(event) {
    const element = event.target;
    const maxScrollHeight = element.scrollHeight - element.offsetHeight;
    const currentScrollPosition = element.scrollTop;

    if (feedbin.shareOpen()) {
      this.show();
    } else if (maxScrollHeight < 40) {
      this.show();
    } else if (currentScrollPosition <= 0) {
      this.show();
    } else if (currentScrollPosition >= maxScrollHeight) {
      this.show();
    } else if (currentScrollPosition > this.lastScrollPosition) {
      this.hide();
    } else if (currentScrollPosition < this.lastScrollPosition) {
      this.show();
    }

    this.lastScrollPosition = currentScrollPosition;
  }

  hide(event) {
    document.body.classList.add(this.cssClass);
  }

  show(event) {
    document.body.classList.remove(this.cssClass);
  }
}
