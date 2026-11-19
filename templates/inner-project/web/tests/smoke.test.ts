import { describe, expect, it } from "vitest";
import { add } from "../src/math.ts";

describe("math smoke test", () => {
  it("adds two numbers", () => {
    expect(add(2, 3)).toBe(5);
  });
});
