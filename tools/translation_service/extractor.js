'use strict';
const fs = require('fs');
const path = require('path');
const ort = require('onnxruntime-node');
const sharp = require('sharp');
const {
  argmaxRow, decodeTokens, postprocessBoxes,
  START, EOS, MAX_STEPS, VOCAB,
} = require('./decode');

const MODELS = path.join(__dirname, 'models');
const DETECTOR_PATH = path.join(MODELS, 'comictextdetector.onnx');
const OCR_PATH = path.join(MODELS, 'manga-ocr', 'model.onnx');
const VOCAB_PATH = path.join(MODELS, 'manga-ocr', 'vocab.txt');

let detector = null;
let ocr = null;
let vocab = [];

async function loadModels() {
  detector = await ort.InferenceSession.create(DETECTOR_PATH, {
    executionProviders: ['cpu'], graphOptimizationLevel: 'all', intraOpNumThreads: 4,
  });
  ocr = await ort.InferenceSession.create(OCR_PATH, {
    executionProviders: ['cpu'], graphOptimizationLevel: 'all', intraOpNumThreads: 4,
  });
  vocab = fs.readFileSync(VOCAB_PATH, 'utf8').split('\n');
}

// sharp raw RGB -> CHW float32，可选归一化 (v/255-mean)/std。
async function toChwTensor(buffer, size, normalize) {
  const { data } = await sharp(buffer).removeAlpha().resize(size, size, { fit: 'fill' })
    .raw().toBuffer({ resolveWithObject: true });
  const plane = size * size;
  const out = new Float32Array(3 * plane);
  for (let i = 0; i < plane; i++) {
    let r = data[i * 3] / 255, g = data[i * 3 + 1] / 255, b = data[i * 3 + 2] / 255;
    if (normalize) { r = (r - 0.5) / 0.5; g = (g - 0.5) / 0.5; b = (b - 0.5) / 0.5; }
    out[i] = r; out[plane + i] = g; out[2 * plane + i] = b;
  }
  return out;
}

async function extractRegions(imageBuffer) {
  if (!detector || !ocr) throw new Error('模型未加载');
  // 1. detector
  const detInput = await toChwTensor(imageBuffer, 1024, false);
  const detTensor = new ort.Tensor('float32', detInput, [1, 3, 1024, 1024]);
  const detOut = await detector.run({ [detector.inputNames[0]]: detTensor });
  const segMap = Array.from(detOut[detector.outputNames[0]].data);
  const boxes = postprocessBoxes(segMap, 1024, 1024, 0.3);

  const meta = await sharp(imageBuffer).metadata();
  const scaleX = meta.width / 1024, scaleY = meta.height / 1024;

  // 2. 逐 box OCR
  const regions = [];
  for (const b of boxes) {
    const ox = Math.round(b[0] * scaleX), oy = Math.round(b[1] * scaleY);
    const ow = Math.max(1, Math.round(b[2] * scaleX));
    const oh = Math.max(1, Math.round(b[3] * scaleY));
    const cropBuf = await sharp(imageBuffer)
      .extract({ left: ox, top: oy, width: ow, height: oh }).toBuffer();
    const text = await runOcr(cropBuf);
    regions.push({ box: [ox, oy, ow, oh], text });
  }
  return regions;
}

async function runOcr(cropBuffer) {
  const imgTensorData = await toChwTensor(cropBuffer, 224, true);
  const imgTensor = new ort.Tensor('float32', imgTensorData, [1, 3, 224, 224]);
  const tokens = [START];
  const imgName = ocr.inputNames[0], tokName = ocr.inputNames[1];
  const logitsName = ocr.outputNames[0];
  for (let step = 0; step < MAX_STEPS; step++) {
    const tokTensor = new ort.Tensor('int64',
      BigInt64Array.from(tokens.map((t) => BigInt(t))), [1, tokens.length]);
    const out = await ocr.run({ [imgName]: imgTensor, [tokName]: tokTensor });
    const logits = out[logitsName].data;
    const lastRow = Array.from(logits.slice(logits.length - VOCAB));
    const next = argmaxRow(lastRow);
    if (next === EOS) break;
    tokens.push(next);
  }
  return decodeTokens(tokens.slice(1), vocab);
}

module.exports = { loadModels, extractRegions };
