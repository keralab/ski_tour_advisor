import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String, interval: { type: Number, default: 3000 } }

  connect()    { this.timer = setInterval(() => { this.element.src = this.urlValue }, this.intervalValue) }
  disconnect() { clearInterval(this.timer) }
}
