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

module.exports = { argmaxRow, decodeTokens, postprocessBoxes, START, EOS, SPECIAL, MAX_STEPS, VOCAB };
