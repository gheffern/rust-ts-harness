import { add } from "./math.ts";

const statusEl = document.getElementById("status");
if (statusEl) {
  statusEl.textContent = `Frontend ready (1 + 2 = ${add(1, 2)})`;
}
