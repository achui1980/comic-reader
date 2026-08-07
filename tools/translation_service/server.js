'use strict';
const express = require('express');
const multer = require('multer');
const { extractRegions, loadModels } = require('./extractor');

const app = express();
const upload = multer({ storage: multer.memoryStorage() });
const PORT = process.env.TRANSLATION_PORT || 9091;

app.get('/health', (req, res) => res.json({ ok: true }));

app.post('/extract', upload.single('image'), async (req, res) => {
  if (!req.file) return res.status(400).json({ error: 'missing image field' });
  try {
    const regions = await extractRegions(req.file.buffer);
    res.json({ regions });
  } catch (e) {
    res.status(500).json({ error: String(e && e.message ? e.message : e) });
  }
});

async function main() {
  await loadModels();
  app.listen(PORT, '127.0.0.1', () => {
    console.log(`翻译推理服务已启动: http://127.0.0.1:${PORT}`);
  });
}

if (require.main === module) {
  main().catch((e) => { console.error('启动失败:', e); process.exit(1); });
}

module.exports = { app };
