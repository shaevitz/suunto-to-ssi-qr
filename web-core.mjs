const FIT_EPOCH_OFFSET_SECONDS = 631_065_600;

export function parseFitDive(buffer) {
  const view = new DataView(buffer);
  if (view.byteLength < 14) throw new Error("This file is too small to be a FIT file.");

  const headerSize = view.getUint8(0);
  const signature = ascii(view, 8, 4);
  if (headerSize < 12 || headerSize >= view.byteLength || signature !== ".FIT") {
    throw new Error("This file does not look like a FIT file.");
  }

  const dataEnd = view.byteLength - 2;
  let offset = headerSize;
  const definitions = new Map();
  const developerFieldNames = new Map();
  const developerFieldBaseTypes = new Map();
  const depthValues = [];
  const temperatures = [];
  let startTime = null;
  let durationSeconds = null;
  let maxDepthMeters = null;

  while (offset < dataEnd) {
    const header = view.getUint8(offset++);
    const isDefinition = (header & 0x40) !== 0;
    const localMessageNumber = header & 0x0f;

    if (isDefinition) {
      const result = readDefinition(view, offset, (header & 0x20) !== 0);
      definitions.set(localMessageNumber, result.definition);
      offset = result.offset;
      continue;
    }

    const definition = definitions.get(localMessageNumber);
    if (!definition) throw new Error("FIT data references a missing message definition.");

    const fields = new Map();
    const developerFields = new Map();
    for (const field of definition.fields) {
      const result = readField(view, offset, field.size, field.baseType, definition.littleEndian);
      fields.set(field.number, result.value);
      offset = result.offset;
    }
    for (const field of definition.developerFields) {
      const result = readField(
        view,
        offset,
        field.size,
        developerFieldBaseTypes.get(field.number),
        definition.littleEndian,
      );
      developerFields.set(field.number, result.value);
      offset = result.offset;
    }

    if (definition.globalMessageNumber === 20) {
      const rawDepth = numberValue(fields.get(92));
      if (rawDepth != null) depthValues.push(rawDepth / 1000);
      const temperature = numberValue(fields.get(13));
      if (temperature != null) temperatures.push(temperature);
    } else if (definition.globalMessageNumber === 18) {
      const rawStart = numberValue(fields.get(2));
      if (rawStart != null) {
        startTime = new Date((rawStart + FIT_EPOCH_OFFSET_SECONDS) * 1000);
      }
      const duration = numberValue(fields.get(8)) ?? numberValue(fields.get(7));
      if (duration != null) durationSeconds = duration / 1000;
      const averageTemperature = numberValue(fields.get(30));
      if (temperatures.length === 0 && averageTemperature != null) {
        temperatures.push(averageTemperature);
      }
      for (const [number, value] of developerFields.entries()) {
        if (developerFieldNames.get(number) === "max_depth") {
          maxDepthMeters = numberValue(value);
        }
      }
    } else if (definition.globalMessageNumber === 206) {
      const fieldNumber = uint8Value(fields.get(1));
      const baseType = uint8Value(fields.get(2));
      const fieldName = textValue(fields.get(3));
      if (fieldNumber != null && fieldName) developerFieldNames.set(fieldNumber, fieldName);
      if (fieldNumber != null && baseType != null) developerFieldBaseTypes.set(fieldNumber, baseType);
    }
  }

  if (!startTime) throw new Error("The FIT file does not contain a dive start time.");
  if (durationSeconds == null) throw new Error("The FIT file does not contain dive duration data.");
  const resolvedDepth = maxDepthMeters ?? Math.max(...depthValues);
  if (!Number.isFinite(resolvedDepth)) throw new Error("The FIT file does not contain dive depth data.");

  return {
    startTime,
    durationSeconds,
    maxDepthMeters: resolvedDepth,
    minimumWaterTemperatureCelsius: temperatures.length ? Math.min(...temperatures) : null,
    maximumWaterTemperatureCelsius: temperatures.length ? Math.max(...temperatures) : null,
  };
}

export function buildSSIPayload(summary, timeZone = Intl.DateTimeFormat().resolvedOptions().timeZone) {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  }).formatToParts(summary.startTime);
  const part = (type) => parts.find((entry) => entry.type === type)?.value;
  const localDateTime = `${part("year")}${part("month")}${part("day")}${part("hour")}${part("minute")}`;
  const fields = [
    "dive",
    "noid",
    "dive_type:0",
    `divetime:${Math.round(summary.durationSeconds / 60)}`,
    `datetime:${localDateTime}`,
    `depth_m:${summary.maxDepthMeters.toFixed(1)}`,
    "user_firstname:",
    "user_lastname:",
  ];
  if (summary.minimumWaterTemperatureCelsius != null) {
    fields.push(`watertemp_c:${formatNumber(summary.minimumWaterTemperatureCelsius)}`);
  }
  if (summary.maximumWaterTemperatureCelsius != null) {
    fields.push(`watertemp_max_c:${formatNumber(summary.maximumWaterTemperatureCelsius)}`);
  }
  return fields.join(";");
}

export function generateQRMatrix(text) {
  if (typeof globalThis.qrcode !== "function") {
    throw new Error("QR generator library is not loaded.");
  }
  const qr = globalThis.qrcode(0, "M");
  qr.addData(text);
  qr.make();
  const size = qr.getModuleCount();
  const modules = Array.from({ length: size }, (_, y) =>
    Array.from({ length: size }, (_, x) => qr.isDark(y, x)),
  );
  return { size, modules };
}

export function drawQRToCanvas(matrix, canvas, scale = 8, border = 4) {
  const pixels = (matrix.size + border * 2) * scale;
  canvas.width = pixels;
  canvas.height = pixels;
  const ctx = canvas.getContext("2d");
  ctx.imageSmoothingEnabled = false;
  ctx.fillStyle = "#ffffff";
  ctx.fillRect(0, 0, pixels, pixels);
  ctx.fillStyle = "#000000";
  for (let y = 0; y < matrix.size; y += 1) {
    for (let x = 0; x < matrix.size; x += 1) {
      if (matrix.modules[y][x]) {
        ctx.fillRect((x + border) * scale, (y + border) * scale, scale, scale);
      }
    }
  }
}

function readDefinition(view, offset, hasDeveloperFields) {
  offset += 1;
  const littleEndian = view.getUint8(offset++) === 0;
  const globalMessageNumber = view.getUint16(offset, littleEndian);
  offset += 2;
  const fieldCount = view.getUint8(offset++);
  const fields = [];
  for (let i = 0; i < fieldCount; i += 1) {
    fields.push({
      number: view.getUint8(offset),
      size: view.getUint8(offset + 1),
      baseType: view.getUint8(offset + 2),
    });
    offset += 3;
  }
  const developerFields = [];
  if (hasDeveloperFields) {
    const developerFieldCount = view.getUint8(offset++);
    for (let i = 0; i < developerFieldCount; i += 1) {
      developerFields.push({
        number: view.getUint8(offset),
        size: view.getUint8(offset + 1),
      });
      offset += 3;
    }
  }
  return { definition: { littleEndian, globalMessageNumber, fields, developerFields }, offset };
}

function readField(view, offset, size, baseType, littleEndian) {
  const normalizedBaseType = baseType == null ? null : baseType & 0x1f;
  let value = null;
  if (normalizedBaseType === 7) {
    value = { type: "text", value: ascii(view, offset, size).replace(/\0.*$/u, "") };
  } else if (size === 1) {
    value = { type: "uint8", value: view.getUint8(offset) };
  } else if (size === 2) {
    value = { type: "number", value: view.getUint16(offset, littleEndian) };
  } else if (size === 4 && normalizedBaseType === 8) {
    value = { type: "number", value: view.getFloat32(offset, littleEndian) };
  } else if (size === 4) {
    value = { type: "number", value: view.getUint32(offset, littleEndian) };
  }
  return { value, offset: offset + size };
}

function ascii(view, offset, length) {
  return String.fromCharCode(...new Uint8Array(view.buffer, view.byteOffset + offset, length));
}

function numberValue(field) {
  return field?.type === "number" || field?.type === "uint8" ? field.value : null;
}

function uint8Value(field) {
  return field?.type === "uint8" || field?.type === "number" ? field.value : null;
}

function textValue(field) {
  return field?.type === "text" ? field.value : null;
}

function formatNumber(value) {
  return Number.isInteger(value) ? String(value) : value.toFixed(1);
}

function encodeByteModeBits(bytes) {
  const bits = [0, 1, 0, 0, ...byteToBits(bytes.length)];
  for (const byte of bytes) bits.push(...byteToBits(byte));
  bits.push(0, 0, 0, 0);
  return bits;
}

function byteToBits(byte) {
  return Array.from({ length: 8 }, (_, index) => (byte >> (7 - index)) & 1);
}

function bitsToByte(bits) {
  return bits.reduce((value, bit) => (value << 1) | bit, 0);
}

function placeFinder(modules, reserved, x, y) {
  for (let dy = -1; dy <= 7; dy += 1) {
    for (let dx = -1; dx <= 7; dx += 1) {
      const px = x + dx;
      const py = y + dy;
      if (!inBounds(modules.length, px, py)) continue;
      const inside = dx >= 0 && dx <= 6 && dy >= 0 && dy <= 6;
      modules[py][px] = inside && (dx === 0 || dx === 6 || dy === 0 || dy === 6 || (dx >= 2 && dx <= 4 && dy >= 2 && dy <= 4));
      reserved[py][px] = true;
    }
  }
}

function placeTiming(modules, reserved) {
  const size = modules.length;
  for (let i = 8; i < size - 8; i += 1) {
    modules[6][i] = i % 2 === 0;
    modules[i][6] = i % 2 === 0;
    reserved[6][i] = true;
    reserved[i][6] = true;
  }
}

function placeAlignment(modules, reserved, x, y) {
  for (let dy = -2; dy <= 2; dy += 1) {
    for (let dx = -2; dx <= 2; dx += 1) {
      const px = x + dx;
      const py = y + dy;
      modules[py][px] = Math.abs(dx) === 2 || Math.abs(dy) === 2 || (dx === 0 && dy === 0);
      reserved[py][px] = true;
    }
  }
}

function reserveFormat(reserved, size) {
  for (let i = 0; i < 9; i += 1) {
    reserved[8][i] = true;
    reserved[i][8] = true;
    reserved[8][size - 1 - i] = true;
    reserved[size - 1 - i][8] = true;
  }
  reserved[size - 8][8] = true;
}

function placeFormatBits(modules, size) {
  const format = 0b101010000010010; // level M, mask 0
  const bits = Array.from({ length: 15 }, (_, i) => ((format >> i) & 1) === 1);
  const coords1 = [[0, 8], [1, 8], [2, 8], [3, 8], [4, 8], [5, 8], [7, 8], [8, 8], [8, 7], [8, 5], [8, 4], [8, 3], [8, 2], [8, 1], [8, 0]];
  const coords2 = [[8, size - 1], [8, size - 2], [8, size - 3], [8, size - 4], [8, size - 5], [8, size - 6], [8, size - 7], [8, size - 8], [size - 7, 8], [size - 6, 8], [size - 5, 8], [size - 4, 8], [size - 3, 8], [size - 2, 8], [size - 1, 8]];
  coords1.forEach(([x, y], i) => { modules[y][x] = bits[i]; });
  coords2.forEach(([x, y], i) => { modules[y][x] = bits[i]; });
  modules[size - 8][8] = true;
}

function placeDataBits(modules, reserved, bits) {
  const size = modules.length;
  let bitIndex = 0;
  let upward = true;
  for (let right = size - 1; right > 0; right -= 2) {
    if (right === 6) right -= 1;
    for (let row = 0; row < size; row += 1) {
      const y = upward ? size - 1 - row : row;
      for (let col = 0; col < 2; col += 1) {
        const x = right - col;
        if (reserved[y][x]) continue;
        modules[y][x] = bits[bitIndex++] === 1;
      }
    }
    upward = !upward;
  }
}

function applyMask(modules, reserved, size) {
  for (let y = 0; y < size; y += 1) {
    for (let x = 0; x < size; x += 1) {
      if (!reserved[y][x] && (x + y) % 2 === 0) {
        modules[y][x] = !modules[y][x];
      }
    }
  }
}

function reedSolomonRemainder(data, degree) {
  const generator = rsGenerator(degree);
  const result = [...data, ...Array(degree).fill(0)];
  for (let i = 0; i < data.length; i += 1) {
    const coefficient = result[i];
    if (coefficient === 0) continue;
    for (let j = 0; j < generator.length; j += 1) {
      result[i + j] ^= gfMultiply(generator[j], coefficient);
    }
  }
  return result.slice(result.length - degree);
}

function rsGenerator(degree) {
  let poly = [1];
  for (let i = 0; i < degree; i += 1) {
    poly = polyMultiply(poly, [1, gfPow(2, i)]);
  }
  return poly;
}

function polyMultiply(a, b) {
  const result = Array(a.length + b.length - 1).fill(0);
  for (let i = 0; i < a.length; i += 1) {
    for (let j = 0; j < b.length; j += 1) {
      result[i + j] ^= gfMultiply(a[i], b[j]);
    }
  }
  return result;
}

function gfPow(value, power) {
  let result = 1;
  for (let i = 0; i < power; i += 1) result = gfMultiply(result, value);
  return result;
}

function gfMultiply(a, b) {
  let result = 0;
  for (let i = 0; i < 8; i += 1) {
    if ((b & 1) !== 0) result ^= a;
    const carry = (a & 0x80) !== 0;
    a = (a << 1) & 0xff;
    if (carry) a ^= 0x1d;
    b >>= 1;
  }
  return result;
}

function inBounds(size, x, y) {
  return x >= 0 && y >= 0 && x < size && y < size;
}
