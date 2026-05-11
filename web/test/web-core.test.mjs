import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { readFile } from "node:fs/promises";
import test from "node:test";

const require = createRequire(import.meta.url);
globalThis.qrcode = require("qrcode-generator");

const {
  buildSSIPayload,
  generateQRMatrix,
  parseFitDive,
} = await import("../web-core.mjs");

test("parses sample Suunto FIT dive", async () => {
  const data = await readFile("test/fixtures/synthetic-dive.fit");
  const summary = parseFitDive(data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength));

  assert.equal(summary.startTime.toISOString(), "2026-05-09T18:35:50.000Z");
  assert.ok(Math.abs(summary.durationSeconds - 575.97) < 0.01);
  assert.ok(Math.abs(summary.maxDepthMeters - 1.34) < 0.01);
  assert.equal(summary.minimumWaterTemperatureCelsius, 31);
  assert.equal(summary.maximumWaterTemperatureCelsius, 32);
});

test("builds SSI payload using local timezone", () => {
  const payload = buildSSIPayload(
    {
      startTime: new Date("2026-05-09T18:35:50.000Z"),
      durationSeconds: 575.97,
      maxDepthMeters: 1.34,
      minimumWaterTemperatureCelsius: 31,
      maximumWaterTemperatureCelsius: 32,
    },
    "America/New_York",
  );

  assert.equal(
    payload,
    "dive;noid;dive_type:0;divetime:10;datetime:202605091435;depth_m:1.3;user_firstname:;user_lastname:;watertemp_c:31;watertemp_max_c:32",
  );
});

test("generates a non-empty QR matrix", () => {
  const matrix = generateQRMatrix("dive;noid;dive_type:0;divetime:10;datetime:202605091435;depth_m:1.3");
  const darkCount = matrix.modules.flat().filter(Boolean).length;

  assert.ok(matrix.size >= 33);
  assert.ok(darkCount > 200);
});
