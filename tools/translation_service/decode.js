'use strict';
const START = 2;
const EOS = 3;
const SPECIAL = 5;
const MAX_STEPS = 300;
const VOCAB = 6144;

function argmaxRow(row) {
  let best = 0;
  let bestVal = row[0];
  for (let i = 1; i < row.length; i++) {
    if (row[i] > bestVal) { bestVal = row[i]; best = i; }
  }
  return best;
}

function decodeTokens(tokenIds, vocab) {
  let out = '';
  for (const id of tokenIds) {
    if (id === EOS) break;
    if (id < SPECIAL) continue;
    if (id < vocab.length) out += vocab[id];
  }
  return out;
}

function postprocessBoxes(segMap, w, h, thresh) {
  const visited = new Array(w * h).fill(false);
  const boxes = [];
  const idx = (x, y) => y * w + x;
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      if (visited[idx(x, y)] || segMap[idx(x, y)] <= thresh) continue;
      let minX = x, maxX = x, minY = y, maxY = y;
      const stack = [[x, y]];
      visited[idx(x, y)] = true;
      while (stack.length) {
        const [px, py] = stack.pop();
        if (px < minX) minX = px;
        if (px > maxX) maxX = px;
        if (py < minY) minY = py;
        if (py > maxY) maxY = py;
        for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
          const nx = px + dx, ny = py + dy;
          if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
          if (visited[idx(nx, ny)] || segMap[idx(nx, ny)] <= thresh) continue;
          visited[idx(nx, ny)] = true;
          stack.push([nx, ny]);
        }
      }
      boxes.push([minX, minY, maxX - minX + 1, maxY - minY + 1]);
    }
  }
  return boxes;
}

// 解析 Manga-Bubble-YOLO 输出。output 是扁平的 [1,300,6] 数据（每行 x1,y1,x2,y2,conf,cls，
// 坐标相对 1280 输入空间）。按 conf>=threshold 过滤，xyxy->原图 xywh（用 scaleX/scaleY 映射回原图）。
// 返回 [[ox,oy,ow,oh]...]。
function parseYoloDetections(output, threshold, scaleX, scaleY) {
  const boxes = [];
  const rows = Math.floor(output.length / 6);
  for (let i = 0; i < rows; i++) {
    const base = i * 6;
    const conf = output[base + 4];
    if (conf < threshold) continue;
    const x1 = output[base];
    const y1 = output[base + 1];
    const x2 = output[base + 2];
    const y2 = output[base + 3];
    const ox = Math.round(x1 * scaleX);
    const oy = Math.round(y1 * scaleY);
    const ow = Math.round((x2 - x1) * scaleX);
    const oh = Math.round((y2 - y1) * scaleY);
    boxes.push([ox, oy, ow, oh]);
  }
  return boxes;
}

module.exports = { argmaxRow, decodeTokens, postprocessBoxes, parseYoloDetections, START, EOS, SPECIAL, MAX_STEPS, VOCAB };
