import { MockCoyoteAdapter } from "./mockCoyoteAdapter.js";
import { RealCoyoteAdapter } from "./realCoyoteAdapter.js";

export function createCoyoteAdapter(config) {
  return config.deviceMode === "real"
    ? new RealCoyoteAdapter(config.coyote)
    : new MockCoyoteAdapter();
}
