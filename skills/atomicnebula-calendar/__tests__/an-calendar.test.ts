import fs from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";

const SCRIPT_PATH = path.resolve(
  __dirname,
  "../scripts/an-calendar.sh",
);

describe("an-calendar helper surface", () => {
  it("keeps empty attendee arrays safe under set -u", () => {
    const source = fs.readFileSync(SCRIPT_PATH, "utf8");

    expect(source).toContain('set -euo pipefail');
    expect(source).toContain('json_string_array_from_args "${required_attendees[@]-}"');
    expect(source).toContain('json_string_array_from_args "${optional_attendees[@]-}"');
  });

  it("documents and calls the assistant calendar targets and write endpoints", () => {
    const source = fs.readFileSync(SCRIPT_PATH, "utf8");

    expect(source).toContain("targets           List accessible calendar mailboxes and calendars");
    expect(source).toContain('"/api/v1/atomicnebula/calendar/targets"');
    expect(source).toContain('"/api/v1/atomicnebula/calendar/events"');
  });
});
