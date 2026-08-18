'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { argmaxRow, decodeTokens, postprocessBoxes, parseYoloDetections, START, EOS } = require('./decode');

test('argmaxRow 取最大下标', () => {
  assert.strictEqual(argmaxRow([0.1, 0.9, 0.3]), 1);
});

test('decodeTokens 跳过特殊 token 并在 EOS 停止', () => {
  const vocab = Array.from({ length: 10 }, (_, i) => 'T' + i);
  assert.strictEqual(decodeTokens([2, 5, 6, 3, 7], vocab), 'T5T6');
});

test('常量正确', () => {
  assert.strictEqual(START, 2);
  assert.strictEqual(EOS, 3);
});

test('postprocessBoxes 提取单块外接框', () => {
  const seg = [
    0, 0, 0, 0,
    0, 1, 1, 0,
    0, 1, 1, 0,
    0, 0, 0, 0,
  ];
  assert.deepStrictEqual(postprocessBoxes(seg, 4, 4, 0.3), [[1, 1, 2, 2]]);
});

test('parseYoloDetections 过滤低置信度并 xyxy->xywh 映射回原图', () => {
  // 两行：第一行 conf 0.9 保留，第二行 conf 0.1 过滤。1280 空间坐标，scale=2 映射到 2560 原图。
  const output = [
    100, 200, 300, 500, 0.9, 0,
    10, 10, 20, 20, 0.1, 0,
  ];
  // x1=100,y1=200,x2=300,y2=500 -> ox=200,oy=400,ow=(300-100)*2=400,oh=(500-200)*2=600
  assert.deepStrictEqual(parseYoloDetections(output, 0.3, 2, 2), [[200, 400, 400, 600]]);
});
