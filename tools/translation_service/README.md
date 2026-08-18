# 漫画翻译本地推理服务 (PoC)

Web 端专用。Native 端不依赖本服务（用 flutter_onnxruntime 进程内推理）。

## 首次初始化（手动，脚本不自动执行）

1. 安装依赖：`cd tools/translation_service && npm install`
2. 下载模型：在仓库根目录运行 `./tools/download_models.sh`
3. 启动服务：`node server.js`（默认端口 9091）

## 接口

POST /extract  (multipart/form-data, 字段名 image)
返回: {"regions": [{"box": [x, y, w, h], "text": "日文原文"}]}
