'use strict';
const fs = require('fs');
const path = require('path');
const ort = require('onnxruntime-node');
const sharp = require('sharp');
const {
  argmaxRow, decodeTokens, parseYoloDetections,
  START, EOS, MAX_STEPS, VOCAB,
} = require('./decode');

const MODELS = path.join(__dirname, 'models');
const DETECTOR_PATH = path.join(MODELS, 'comic-bubble-yolo.onnx');
const OCR_ENCODER_PATH = path.join(MODELS, 'manga-ocr', 'encoder_model.onnx');
const OCR_DECODER_PATH = path.join(MODELS, 'manga-ocr', 'decoder_model.onnx');
const VOCAB_PATH = path.join(MODELS, 'manga-ocr', 'vocab.txt');

let detector = null;
let ocrEncoder = null;
let ocrDecoder = null;
let vocab = [];

async function loadModels() {
  detector = await ort.InferenceSession.create(DETECTOR_PATH, {
    executionProviders: ['cpu'], graphOptimizationLevel: 'all', intraOpNumThreads: 4,
  });
  ocrEncoder = await ort.InferenceSession.create(OCR_ENCODER_PATH, {
    executionProviders: ['cpu'], graphOptimizationLevel: 'all', intraOpNumThreads: 4,
  });
  ocrDecoder = await ort.InferenceSession.create(OCR_DECODER_PATH, {
    executionProviders: ['cpu'], graphOptimizationLevel: 'all', intraOpNumThreads: 4,
  });
  vocab = fs.readFileSync(VOCAB_PATH, 'utf8').split('\n').map((l) => l.replace(/\r/g, ''));
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
  if (!detector || !ocrEncoder || !ocrDecoder) throw new Error('模型未加载');
  // 1. detector: Manga-Bubble-YOLO，输入 1280，输出 output0 [1,300,6] 每行 x1,y1,x2,y2,conf,cls。
  const detInput = await toChwTensor(imageBuffer, 1280, false);
  const detTensor = new ort.Tensor('float32', detInput, [1, 3, 1280, 1280]);
  const detOut = await detector.run({ [detector.inputNames[0]]: detTensor });

  const meta = await sharp(imageBuffer).metadata();
  const scaleX = meta.width / 1280, scaleY = meta.height / 1280;
  const boxes = parseYoloDetections(Array.from(detOut.output0.data), 0.3, scaleX, scaleY);

  // 2. 逐 box OCR。boxes 已是映射回原图的 xywh，只需 clamp 防越界。
  const regions = [];
  for (const b of boxes) {
    const ox = Math.max(0, Math.min(b[0], meta.width - 1));
    const oy = Math.max(0, Math.min(b[1], meta.height - 1));
    const ow = Math.max(1, Math.min(b[2], meta.width - ox));
    const oh = Math.max(1, Math.min(b[3], meta.height - oy));
    const cropBuf = await sharp(imageBuffer)
      .extract({ left: ox, top: oy, width: ow, height: oh }).toBuffer();
    const text = await runOcr(cropBuf);
    regions.push({ box: [ox, oy, ow, oh], text });
  }
  return regions;
}

// manga-ocr 是 VisionEncoderDecoder 双文件模型：
// 先 encoder(pixel_values -> last_hidden_state[1,197,768])，
// 再 decoder 贪婪循环(input_ids + encoder_hidden_states -> logits[1,seq,6144])。
async function runOcr(cropBuffer) {
  const imgTensorData = await toChwTensor(cropBuffer, 224, true);
  const pixelValues = new ort.Tensor('float32', imgTensorData, [1, 3, 224, 224]);
  const encOut = await ocrEncoder.run({ [ocrEncoder.inputNames[0]]: pixelValues });
  const hidden = encOut.last_hidden_state;

  const tokens = [START];
  for (let step = 0; step < MAX_STEPS; step++) {
    const idsTensor = new ort.Tensor('int64',
      BigInt64Array.from(tokens.map((t) => BigInt(t))), [1, tokens.length]);
    const out = await ocrDecoder.run({
      input_ids: idsTensor,
      encoder_hidden_states: hidden,
    });
    const logits = out.logits.data;
    // logits 形状 [1, seq, 6144]，取最后一行 vocab logits。
    const lastRow = Array.from(logits.slice(logits.length - VOCAB));
    const next = argmaxRow(lastRow);
    if (next === EOS) break;
    tokens.push(next);
  }
  return decodeTokens(tokens.slice(1), vocab);
}

module.exports = { loadModels, extractRegions };
