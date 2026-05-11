import {
  buildSSIPayload,
  drawQRToCanvas,
  generateQRMatrix,
  parseFitDive,
} from "./web-core.mjs";

const input = document.querySelector("#fit-input");
const dropZone = document.querySelector("#drop-zone");
const status = document.querySelector("#status");
const result = document.querySelector("#result");
const canvas = document.querySelector("#qr-canvas");
const summaryList = document.querySelector("#summary");
const payloadField = document.querySelector("#payload");
const downloadLink = document.querySelector("#download-link");
const shareButton = document.querySelector("#share-button");

let latestBlob = null;
let latestFileName = "ssi-dive-qr.png";

input.addEventListener("change", () => {
  const file = input.files?.[0];
  if (file) convertFile(file);
});

dropZone.addEventListener("dragover", (event) => {
  event.preventDefault();
  dropZone.classList.add("dragging");
});

dropZone.addEventListener("dragleave", () => {
  dropZone.classList.remove("dragging");
});

dropZone.addEventListener("drop", (event) => {
  event.preventDefault();
  dropZone.classList.remove("dragging");
  const file = event.dataTransfer?.files?.[0];
  if (file) convertFile(file);
});

shareButton.addEventListener("click", async () => {
  if (!latestBlob) return;
  const file = new File([latestBlob], latestFileName, { type: "image/png" });
  if (navigator.canShare?.({ files: [file] })) {
    await navigator.share({ files: [file], title: "SSI Dive QR" });
  } else if (navigator.share) {
    await navigator.share({ title: "SSI Dive QR", text: payloadField.value });
  }
});

if ("serviceWorker" in navigator) {
  navigator.serviceWorker.register("./sw.js").catch(() => {});
}

async function convertFile(file) {
  try {
    status.textContent = `Reading ${file.name}...`;
    const buffer = await file.arrayBuffer();
    const summary = parseFitDive(buffer);
    const payload = buildSSIPayload(summary);
    const matrix = generateQRMatrix(payload);

    drawQRToCanvas(matrix, canvas, window.devicePixelRatio >= 2 ? 10 : 8, 4);
    latestBlob = await canvasToBlob(canvas);
    latestFileName = `${stem(file.name)}_ssi_qr.png`;
    downloadLink.href = URL.createObjectURL(latestBlob);
    downloadLink.download = latestFileName;

    renderSummary(summary);
    payloadField.value = payload;
    result.classList.remove("hidden");
    status.textContent = `Created ${latestFileName}.`;
  } catch (error) {
    result.classList.add("hidden");
    status.textContent = error instanceof Error ? error.message : String(error);
  }
}

function renderSummary(summary) {
  const formatter = new Intl.DateTimeFormat(undefined, {
    dateStyle: "medium",
    timeStyle: "short",
  });
  const rows = [
    ["Start", formatter.format(summary.startTime)],
    ["Duration", `${Math.round(summary.durationSeconds / 60)} min`],
    ["Max depth", `${summary.maxDepthMeters.toFixed(1)} m`],
  ];
  if (summary.minimumWaterTemperatureCelsius != null && summary.maximumWaterTemperatureCelsius != null) {
    rows.push([
      "Water temp",
      `${formatNumber(summary.minimumWaterTemperatureCelsius)}-${formatNumber(summary.maximumWaterTemperatureCelsius)} C`,
    ]);
  }
  summaryList.replaceChildren(...rows.flatMap(([label, value]) => {
    const dt = document.createElement("dt");
    const dd = document.createElement("dd");
    dt.textContent = label;
    dd.textContent = value;
    return [dt, dd];
  }));
}

function canvasToBlob(target) {
  return new Promise((resolve, reject) => {
    target.toBlob((blob) => {
      if (blob) resolve(blob);
      else reject(new Error("Could not create QR PNG."));
    }, "image/png");
  });
}

function stem(fileName) {
  return fileName.replace(/\.[^.]+$/u, "");
}

function formatNumber(value) {
  return Number.isInteger(value) ? String(value) : value.toFixed(1);
}
