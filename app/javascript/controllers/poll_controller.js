import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { interval: { type: Number, default: 3000 } }

  connect()    { this.timer = setInterval(() => { this.element.reload() }, this.intervalValue) }
  disconnect() { clearInterval(this.timer) }
}
