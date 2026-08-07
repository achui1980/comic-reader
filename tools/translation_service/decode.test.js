'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { argmaxRow, decodeTokens, postprocessBoxes, START, EOS } = require('./decode');

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
