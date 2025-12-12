# markdown2png 微信小程序迁移方案

> 基于云函数的混合架构方案，实现完整功能迁移

## 目录

1. [项目概述](#1-项目概述)
2. [架构设计](#2-架构设计)
3. [技术选型](#3-技术选型)
4. [功能模块迁移](#4-功能模块迁移)
5. [云函数设计](#5-云函数设计)
6. [前端实现](#6-前端实现)
7. [数据存储方案](#7-数据存储方案)
8. [开发计划](#8-开发计划)
9. [注意事项](#9-注意事项)

---

## 1. 项目概述

### 1.1 原项目功能

| 功能模块 | 描述 |
|---------|------|
| Home 模式 | Markdown 文本转图片，支持 19 种主题 |
| Digest 模式 | 书摘美化，Canvas 绘制，自定义字体/背景 |
| 图片导出 | 复制到剪贴板、下载为 PNG |
| 滤镜效果 | 黑白、复古、鲜艳等图片滤镜 |
| 本地存储 | 内容、主题、样式设置持久化 |

### 1.2 迁移目标

- **功能保留度**：95%+
- **用户体验**：接近原 Web 版
- **性能要求**：图片生成 < 3 秒

### 1.3 技术挑战

| 原技术 | 问题 | 解决方案 |
|-------|------|---------|
| snapdom (WASM) | 小程序不支持 | 云函数 + Puppeteer |
| photon (WASM) | 小程序不支持 | 云函数 + Sharp |
| document.fonts | 小程序不支持 | 云端字体渲染 |
| navigator.clipboard | 小程序不支持 | 保存相册 + 分享 |

---

## 2. 架构设计

### 2.1 整体架构

```
┌────────────────────────────────────────────────────────────┐
│                    微信小程序前端                           │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │  Markdown    │  │   Digest     │  │    设置      │     │
│  │  编辑页面    │  │   编辑页面   │  │    页面      │     │
│  └──────┬───────┘  └──────┬───────┘  └──────────────┘     │
│         │                 │                                │
│  ┌──────▼─────────────────▼───────┐                       │
│  │         Canvas 预览层           │                       │
│  │    (简单场景本地渲染预览)        │                       │
│  └──────────────┬─────────────────┘                       │
└─────────────────┼──────────────────────────────────────────┘
                  │
                  │ HTTPS 请求
                  ▼
┌────────────────────────────────────────────────────────────┐
│                    微信云开发                               │
│  ┌──────────────────────────────────────────────────────┐ │
│  │                    云函数层                           │ │
│  │  ┌────────────┐ ┌────────────┐ ┌────────────┐       │ │
│  │  │ renderImage│ │applyFilter │ │ uploadFont │       │ │
│  │  │ 图片渲染   │ │ 滤镜处理   │ │ 字体管理   │       │ │
│  │  └─────┬──────┘ └─────┬──────┘ └────────────┘       │ │
│  │        │              │                              │ │
│  │  ┌─────▼──────────────▼─────┐                       │ │
│  │  │      Node.js 运行时       │                       │ │
│  │  │  • Puppeteer (DOM渲染)   │                       │ │
│  │  │  • Sharp (图片处理)       │                       │ │
│  │  │  • node-canvas (绘制)    │                       │ │
│  │  └──────────────────────────┘                       │ │
│  └──────────────────────────────────────────────────────┘ │
│                                                            │
│  ┌──────────────────────────────────────────────────────┐ │
│  │                    云存储                             │ │
│  │  • 生成的图片 (临时/永久)                             │ │
│  │  • 用户上传的背景图                                   │ │
│  │  • 自定义字体文件                                     │ │
│  └──────────────────────────────────────────────────────┘ │
│                                                            │
│  ┌──────────────────────────────────────────────────────┐ │
│  │                    云数据库                           │ │
│  │  • 用户设置                                          │ │
│  │  • 书摘历史                                          │ │
│  │  • 使用统计                                          │ │
│  └──────────────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────────────┘
```

### 2.2 数据流

```
用户输入 Markdown
       │
       ▼
┌─────────────────┐
│  本地预览渲染    │  ← 简化版 Canvas 渲染（实时）
└────────┬────────┘
         │
         │ 点击"生成图片"
         ▼
┌─────────────────┐
│  调用云函数      │  ← 发送: content, theme, settings
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  云端渲染图片    │  ← Puppeteer 渲染完整 HTML
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  返回图片 URL    │  ← 云存储临时链接
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  保存/分享       │  ← wx.saveImageToPhotosAlbum
└─────────────────┘
```

---

## 3. 技术选型

### 3.1 前端技术栈

| 技术 | 选择 | 理由 |
|-----|------|------|
| 框架 | 原生小程序 / Taro | 原生性能好，Taro 可复用 Vue 代码 |
| UI 组件 | Vant Weapp | 成熟稳定，组件丰富 |
| 状态管理 | MobX-miniprogram | 类似 Pinia 的响应式 |
| Markdown | marked | 纯 JS，直接可用 |
| 样式 | WXSS + Less | 支持变量和嵌套 |

### 3.2 云函数技术栈

| 技术 | 版本 | 用途 |
|-----|------|------|
| Node.js | 16.x / 18.x | 运行时 |
| Puppeteer | ^21.0.0 | DOM 渲染为图片 |
| Sharp | ^0.33.0 | 图片处理、滤镜 |
| node-canvas | ^2.11.0 | Canvas 绘制（备选） |
| marked | ^10.0.0 | Markdown 解析 |

### 3.3 推荐框架选择

**方案 A：原生小程序（推荐新手）**
```
miniprogram/
├── pages/
├── components/
├── utils/
└── cloud/
    └── functions/
```

**方案 B：Taro + Vue3（推荐，可复用代码）**
```
src/
├── pages/
├── components/    ← 可部分复用原项目组件
├── stores/        ← 可复用 Pinia store 逻辑
└── cloud/
    └── functions/
```

---

## 4. 功能模块迁移

### 4.1 Home 模式（Markdown 转图片）

#### 原实现
```typescript
// 使用 snapdom 将 DOM 转为图片
import { snapdom } from '@zumer/snapdom'
imageBlob = await snapdom.toBlob(container, options)
```

#### 小程序实现

**前端部分**：
```typescript
// pages/home/home.ts
Page({
  data: {
    content: '',
    theme: 'note',
    size: 'mobile',
    isWithDate: false,
    previewHtml: '',
    isGenerating: false
  },

  // Markdown 实时预览（本地简化渲染）
  onContentChange(e: any) {
    const content = e.detail.value
    this.setData({ content })

    // 使用 marked 解析
    const html = marked.parse(content, { breaks: true })
    this.setData({ previewHtml: html })

    // 保存到本地
    wx.setStorageSync('current-content', content)
  },

  // 生成高清图片（调用云函数）
  async generateImage() {
    this.setData({ isGenerating: true })

    try {
      const result = await wx.cloud.callFunction({
        name: 'renderImage',
        data: {
          type: 'markdown',
          content: this.data.content,
          theme: this.data.theme,
          size: this.data.size,
          isWithDate: this.data.isWithDate
        }
      })

      const { imageUrl } = result.result as any

      // 下载并保存
      await this.saveImage(imageUrl)
    } catch (error) {
      wx.showToast({ title: '生成失败', icon: 'error' })
    } finally {
      this.setData({ isGenerating: false })
    }
  },

  // 保存图片到相册
  async saveImage(url: string) {
    const { tempFilePath } = await wx.downloadFile({ url })

    await wx.saveImageToPhotosAlbum({ filePath: tempFilePath })
    wx.showToast({ title: '已保存到相册', icon: 'success' })
  }
})
```

**云函数部分**：见 [5.1 renderImage 云函数](#51-renderimage-云函数)

### 4.2 Digest 模式（书摘美化）

#### 原实现
```typescript
// Canvas 2D 绘制
const ctx = canvas.getContext('2d')
ctx.drawImage(backgroundImage, 0, 0)
ctx.font = `${fontSize}px ${fontFamily}`
ctx.fillText(text, x, y)
```

#### 小程序实现

**前端部分（本地 Canvas 预览）**：
```typescript
// pages/digest/digest.ts
Page({
  data: {
    digest: '',
    fontSize: 16,
    fontFamily: 'system-ui',
    textColor: '#000000',
    textAlign: 'center',
    lineHeight: 2,
    letterSpacing: 20,
    selectedBg: 0,
    backgrounds: [
      '/assets/bg/bg0.png',
      '/assets/bg/bg1.png',
      // ...
    ]
  },

  canvasCtx: null as any,

  onReady() {
    // 初始化 Canvas
    const query = wx.createSelectorQuery()
    query.select('#digestCanvas')
      .fields({ node: true, size: true })
      .exec((res) => {
        const canvas = res[0].node
        this.canvasCtx = canvas.getContext('2d')
        this.drawPreview()
      })
  },

  // 本地预览绘制（简化版，使用系统字体）
  async drawPreview() {
    const ctx = this.canvasCtx
    const { digest, fontSize, textColor, textAlign } = this.data

    // 清空画布
    ctx.clearRect(0, 0, 500, 660)

    // 绘制背景
    const bgPath = this.data.backgrounds[this.data.selectedBg]
    const bgImage = await this.loadImage(bgPath)
    ctx.drawImage(bgImage, 0, 0, 500, 660)

    // 绘制文本（简化版）
    ctx.font = `${fontSize}px system-ui`
    ctx.fillStyle = textColor
    ctx.textAlign = textAlign as CanvasTextAlign

    // 文本换行处理
    const lines = this.wrapText(digest, 400)
    const lineHeight = fontSize * this.data.lineHeight
    let y = (660 - lines.length * lineHeight) / 2

    lines.forEach(line => {
      const x = textAlign === 'center' ? 250 : 50
      ctx.fillText(line, x, y)
      y += lineHeight
    })
  },

  // 生成高清图片（云函数渲染，支持自定义字体）
  async generateHighQualityImage() {
    wx.showLoading({ title: '生成中...' })

    try {
      const result = await wx.cloud.callFunction({
        name: 'renderImage',
        data: {
          type: 'digest',
          content: this.data.digest,
          settings: {
            fontSize: this.data.fontSize,
            fontFamily: this.data.fontFamily,
            textColor: this.data.textColor,
            textAlign: this.data.textAlign,
            lineHeight: this.data.lineHeight,
            letterSpacing: this.data.letterSpacing,
            backgroundIndex: this.data.selectedBg
          }
        }
      })

      const { imageUrl } = result.result as any
      await this.saveImage(imageUrl)
    } finally {
      wx.hideLoading()
    }
  },

  // 文本换行
  wrapText(text: string, maxWidth: number): string[] {
    const ctx = this.canvasCtx
    const lines: string[] = []
    let currentLine = ''

    for (const char of text) {
      const testLine = currentLine + char
      const { width } = ctx.measureText(testLine)

      if (width > maxWidth && currentLine) {
        lines.push(currentLine)
        currentLine = char
      } else {
        currentLine = testLine
      }
    }

    if (currentLine) lines.push(currentLine)
    return lines
  },

  // 加载图片
  loadImage(src: string): Promise<any> {
    return new Promise((resolve, reject) => {
      const img = this.canvasCtx.canvas.createImage()
      img.onload = () => resolve(img)
      img.onerror = reject
      img.src = src
    })
  }
})
```

### 4.3 主题系统迁移

#### 原主题定义
```typescript
// src/helper/constant.ts
export const THEME_ARR = [
  { name: '便签', id: 'note' },
  { name: '元气', id: 'vitality' },
  // ... 19 种主题
]
```

#### 小程序实现

**主题配置**：
```typescript
// miniprogram/config/themes.ts
export const THEMES = [
  {
    id: 'note',
    name: '便签',
    background: '#fffcf5',
    contentBg: '#fffcf5',
    border: '1px solid #e8e5dc',
    textColor: '#333333'
  },
  {
    id: 'vitality',
    name: '元气',
    background: 'linear-gradient(225deg, #9cccfc 0, #e6cefd 99.54%)',
    contentBg: '#f2f2f2',
    borderRadius: '1rem',
    textColor: '#333333'
  },
  {
    id: 'dark',
    name: '暗黑',
    background: 'linear-gradient(to right, #434343 0%, black 100%)',
    contentBg: 'transparent',
    textColor: '#f2f2f2'
  },
  // ... 其他主题
]

// 主题对应的完整 CSS（用于云函数渲染）
export const THEME_CSS: Record<string, string> = {
  note: `
    .container { background-color: #fffcf5; }
    .content { border: 1px solid #e8e5dc; position: relative; }
    .content::before {
      position: absolute;
      content: '';
      left: 3px; right: 3px; bottom: 3px; top: 3px;
      border: 1px solid #e8e5dc;
    }
  `,
  vitality: `
    .container { background: linear-gradient(225deg, #9cccfc 0, #e6cefd 99.54%); }
    .content { background-color: #f2f2f2; border-radius: 1rem; }
  `,
  // ... 其他主题 CSS
}
```

### 4.4 滤镜功能迁移

#### 原实现
```typescript
// 使用 WASM 库 photon
import('@silvia-odwyer/photon').then((photon) => {
  const image = photon.open_image(canvas, ctx)
  photon.filter(image, 'oceanic')
  photon.putImageData(canvas, ctx, image)
})
```

#### 小程序实现

**前端调用**：
```typescript
// 应用滤镜
async applyFilter(filterType: string) {
  wx.showLoading({ title: '处理中...' })

  try {
    const result = await wx.cloud.callFunction({
      name: 'applyFilter',
      data: {
        imageFileId: this.data.currentImageFileId,
        filterType: filterType // 'grayscale' | 'sepia' | 'oceanic' | ...
      }
    })

    const { imageUrl } = result.result as any
    this.setData({ filteredImageUrl: imageUrl })
  } finally {
    wx.hideLoading()
  }
}
```

**云函数实现**：见 [5.2 applyFilter 云函数](#52-applyfilter-云函数)

---

## 5. 云函数设计

### 5.1 renderImage 云函数

**功能**：将 Markdown/Digest 内容渲染为高清图片

**目录结构**：
```
cloud/functions/renderImage/
├── index.js
├── package.json
├── templates/
│   ├── markdown.html      # Markdown 渲染模板
│   └── digest.html        # Digest 渲染模板
├── themes/
│   └── themes.css         # 所有主题样式
└── fonts/
    ├── NotoSansSC.woff2
    ├── ShouJinTi.woff2
    └── ...
```

**package.json**：
```json
{
  "name": "renderImage",
  "version": "1.0.0",
  "main": "index.js",
  "dependencies": {
    "wx-server-sdk": "^2.6.3",
    "puppeteer-core": "^21.0.0",
    "@sparticuz/chromium": "^119.0.0",
    "marked": "^10.0.0"
  }
}
```

**index.js**：
```javascript
const cloud = require('wx-server-sdk')
const puppeteer = require('puppeteer-core')
const chromium = require('@sparticuz/chromium')
const { marked } = require('marked')
const fs = require('fs')
const path = require('path')

cloud.init({ env: cloud.DYNAMIC_CURRENT_ENV })

// 主题 CSS
const THEME_CSS = fs.readFileSync(
  path.join(__dirname, 'themes/themes.css'),
  'utf-8'
)

// Markdown 模板
const MARKDOWN_TEMPLATE = fs.readFileSync(
  path.join(__dirname, 'templates/markdown.html'),
  'utf-8'
)

// Digest 模板
const DIGEST_TEMPLATE = fs.readFileSync(
  path.join(__dirname, 'templates/digest.html'),
  'utf-8'
)

// 尺寸配置
const SIZES = {
  mobile: { width: 320, padding: '3rem' },
  tablet: { width: 600, padding: '3rem' },
  laptop: { width: 800, padding: '3rem' },
  desktop: { width: 960, padding: '3rem' }
}

// Digest 比例配置
const RATIOS = {
  default: { width: 500, height: 660 },
  xiaohongshu: { width: 540, height: 720 },
  douyin: { width: 540, height: 768 },
  square: { width: 600, height: 600 },
  weixin: { width: 900, height: 500 }
}

exports.main = async (event, context) => {
  const { type, content, theme, size, settings, isWithDate } = event

  let browser = null

  try {
    // 启动浏览器
    browser = await puppeteer.launch({
      args: chromium.args,
      defaultViewport: chromium.defaultViewport,
      executablePath: await chromium.executablePath(),
      headless: chromium.headless
    })

    const page = await browser.newPage()

    let html = ''
    let viewport = { width: 800, height: 600 }

    if (type === 'markdown') {
      // Markdown 模式
      const parsedContent = marked.parse(content, { breaks: true })
      const sizeConfig = SIZES[size] || SIZES.mobile

      // 添加日期
      let dateHtml = ''
      if (isWithDate) {
        const today = new Date().toISOString().split('T')[0]
        dateHtml = `<p style="text-align: right;"><time>${today}</time></p>`
      }

      html = MARKDOWN_TEMPLATE
        .replace('{{THEME_CSS}}', THEME_CSS)
        .replace('{{THEME_CLASS}}', `${theme}-box`)
        .replace('{{CONTENT_CLASS}}', theme)
        .replace('{{CONTENT}}', parsedContent + dateHtml)
        .replace('{{WIDTH}}', `${sizeConfig.width}px`)
        .replace('{{PADDING}}', sizeConfig.padding)

      viewport = { width: sizeConfig.width + 100, height: 800 }

    } else if (type === 'digest') {
      // Digest 模式
      const ratio = RATIOS[settings.selectedRatio] || RATIOS.default
      const bgUrl = getBackgroundUrl(settings.backgroundIndex)

      html = DIGEST_TEMPLATE
        .replace('{{WIDTH}}', `${ratio.width}px`)
        .replace('{{HEIGHT}}', `${ratio.height}px`)
        .replace('{{BACKGROUND_URL}}', bgUrl)
        .replace('{{FONT_SIZE}}', `${settings.fontSize}px`)
        .replace('{{FONT_FAMILY}}', settings.fontFamily)
        .replace('{{TEXT_COLOR}}', settings.textColor)
        .replace('{{TEXT_ALIGN}}', settings.textAlign)
        .replace('{{LINE_HEIGHT}}', settings.lineHeight)
        .replace('{{LETTER_SPACING}}', `${settings.letterSpacing / 50}em`)
        .replace('{{CONTENT}}', parseDigestMarkdown(content))

      viewport = { width: ratio.width, height: ratio.height }
    }

    await page.setViewport(viewport)
    await page.setContent(html, { waitUntil: 'networkidle0' })

    // 等待字体加载
    await page.evaluate(() => document.fonts.ready)

    // 截图
    const element = await page.$('#container')
    const screenshot = await element.screenshot({
      type: 'png',
      omitBackground: false
    })

    // 上传到云存储
    const fileName = `images/${Date.now()}-${Math.random().toString(36).slice(2)}.png`
    const uploadResult = await cloud.uploadFile({
      cloudPath: fileName,
      fileContent: screenshot
    })

    // 获取临时链接
    const { fileList } = await cloud.getTempFileURL({
      fileList: [uploadResult.fileID]
    })

    return {
      success: true,
      imageUrl: fileList[0].tempFileURL,
      fileId: uploadResult.fileID
    }

  } catch (error) {
    console.error('渲染失败:', error)
    return {
      success: false,
      error: error.message
    }
  } finally {
    if (browser) {
      await browser.close()
    }
  }
}

// 获取背景图 URL
function getBackgroundUrl(index) {
  const backgrounds = [
    'https://your-cdn.com/bg/bg0.png',
    'https://your-cdn.com/bg/bg1.png',
    // ... 预置背景图
  ]
  return backgrounds[index] || backgrounds[0]
}

// 解析 Digest Markdown（**加粗** __下划线__ ==高亮== ~~删除线~~）
function parseDigestMarkdown(text) {
  return text
    .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
    .replace(/__(.+?)__/g, '<u>$1</u>')
    .replace(/==(.+?)==/g, '<mark>$1</mark>')
    .replace(/~~(.+?)~~/g, '<del>$1</del>')
    .replace(/\n/g, '<br>')
}
```

**templates/markdown.html**：
```html
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }

    body {
      font-family: 'Noto Sans SC', 'PingFang SC', 'Microsoft YaHei', sans-serif;
    }

    /* 主题样式 */
    {{THEME_CSS}}

    #container {
      width: {{WIDTH}};
      padding: {{PADDING}};
    }

    .content {
      padding: 1rem;
    }

    .markdown {
      line-height: 1.8;
    }

    .markdown h1, .markdown h2, .markdown h3 {
      margin: 1em 0 0.5em;
    }

    .markdown p {
      margin: 0.5em 0;
    }

    .markdown code {
      background: rgba(0,0,0,0.05);
      padding: 0.2em 0.4em;
      border-radius: 3px;
    }

    .markdown pre {
      background: rgba(0,0,0,0.05);
      padding: 1em;
      border-radius: 5px;
      overflow-x: auto;
    }

    .markdown ul, .markdown ol {
      padding-left: 2em;
    }

    .markdown blockquote {
      border-left: 4px solid #ddd;
      padding-left: 1em;
      color: #666;
    }
  </style>
</head>
<body>
  <div id="container" class="{{THEME_CLASS}}">
    <div class="content {{CONTENT_CLASS}}">
      <div class="markdown">
        {{CONTENT}}
      </div>
    </div>
  </div>
</body>
</html>
```

**templates/digest.html**：
```html
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <style>
    @font-face {
      font-family: 'Noto Sans SC';
      src: url('https://your-cdn.com/fonts/NotoSansSC-Regular.woff2') format('woff2');
    }
    @font-face {
      font-family: 'ShouJinTi';
      src: url('https://your-cdn.com/fonts/ShouJinTi.woff2') format('woff2');
    }
    @font-face {
      font-family: 'Huiwen-Fangsong';
      src: url('https://your-cdn.com/fonts/Huiwen-Fangsong.woff2') format('woff2');
    }
    /* 其他字体... */

    * { margin: 0; padding: 0; box-sizing: border-box; }

    #container {
      width: {{WIDTH}};
      height: {{HEIGHT}};
      background-image: url('{{BACKGROUND_URL}}');
      background-size: cover;
      background-position: center;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 40px;
    }

    .content {
      font-size: {{FONT_SIZE}};
      font-family: {{FONT_FAMILY}}, 'Noto Sans SC', sans-serif;
      color: {{TEXT_COLOR}};
      text-align: {{TEXT_ALIGN}};
      line-height: {{LINE_HEIGHT}};
      letter-spacing: {{LETTER_SPACING}};
      word-break: break-word;
    }

    .content strong { font-weight: bold; }
    .content u { text-decoration: underline; }
    .content del { text-decoration: line-through; }
    .content mark {
      background: linear-gradient(180deg, transparent 60%, #fff176 60%);
      padding: 0 2px;
    }
  </style>
</head>
<body>
  <div id="container">
    <div class="content">
      {{CONTENT}}
    </div>
  </div>
</body>
</html>
```

### 5.2 applyFilter 云函数

**功能**：为图片应用滤镜效果

**package.json**：
```json
{
  "name": "applyFilter",
  "version": "1.0.0",
  "main": "index.js",
  "dependencies": {
    "wx-server-sdk": "^2.6.3",
    "sharp": "^0.33.0"
  }
}
```

**index.js**：
```javascript
const cloud = require('wx-server-sdk')
const sharp = require('sharp')

cloud.init({ env: cloud.DYNAMIC_CURRENT_ENV })

// 滤镜配置
const FILTERS = {
  // 灰度
  grayscale: (image) => image.grayscale(),

  // 复古（棕褐色）
  sepia: (image) => image.recomb([
    [0.393, 0.769, 0.189],
    [0.349, 0.686, 0.168],
    [0.272, 0.534, 0.131]
  ]),

  // 高对比度
  contrast: (image) => image.linear(1.5, -(128 * 1.5) + 128),

  // 柔和
  soft: (image) => image.blur(0.5).modulate({ saturation: 0.8 }),

  // 鲜艳
  vivid: (image) => image.modulate({ saturation: 1.5 }),

  // 冷色调
  cool: (image) => image.tint({ r: 200, g: 220, b: 255 }),

  // 暖色调
  warm: (image) => image.tint({ r: 255, g: 220, b: 200 }),

  // 反转
  invert: (image) => image.negate(),

  // 模糊
  blur: (image) => image.blur(5),

  // 锐化
  sharpen: (image) => image.sharpen()
}

exports.main = async (event, context) => {
  const { imageFileId, filterType } = event

  try {
    // 下载原图
    const { fileContent } = await cloud.downloadFile({
      fileID: imageFileId
    })

    // 应用滤镜
    let image = sharp(fileContent)

    if (FILTERS[filterType]) {
      image = FILTERS[filterType](image)
    } else {
      throw new Error(`未知滤镜类型: ${filterType}`)
    }

    // 输出为 PNG
    const outputBuffer = await image.png().toBuffer()

    // 上传处理后的图片
    const fileName = `filtered/${Date.now()}-${filterType}.png`
    const uploadResult = await cloud.uploadFile({
      cloudPath: fileName,
      fileContent: outputBuffer
    })

    // 获取临时链接
    const { fileList } = await cloud.getTempFileURL({
      fileList: [uploadResult.fileID]
    })

    return {
      success: true,
      imageUrl: fileList[0].tempFileURL,
      fileId: uploadResult.fileID
    }

  } catch (error) {
    console.error('滤镜处理失败:', error)
    return {
      success: false,
      error: error.message
    }
  }
}
```

### 5.3 uploadBackground 云函数

**功能**：上传用户自定义背景图

```javascript
const cloud = require('wx-server-sdk')
const sharp = require('sharp')

cloud.init({ env: cloud.DYNAMIC_CURRENT_ENV })

exports.main = async (event, context) => {
  const { fileID } = event
  const { OPENID } = cloud.getWXContext()

  try {
    // 下载用户上传的图片
    const { fileContent } = await cloud.downloadFile({ fileID })

    // 压缩和优化图片
    const optimized = await sharp(fileContent)
      .resize(1080, 1440, {
        fit: 'cover',
        withoutEnlargement: true
      })
      .jpeg({ quality: 85 })
      .toBuffer()

    // 存储到用户目录
    const fileName = `backgrounds/${OPENID}/${Date.now()}.jpg`
    const uploadResult = await cloud.uploadFile({
      cloudPath: fileName,
      fileContent: optimized
    })

    // 删除临时文件
    await cloud.deleteFile({ fileList: [fileID] })

    // 获取永久链接
    const { fileList } = await cloud.getTempFileURL({
      fileList: [uploadResult.fileID]
    })

    return {
      success: true,
      fileId: uploadResult.fileID,
      imageUrl: fileList[0].tempFileURL
    }

  } catch (error) {
    console.error('上传背景失败:', error)
    return {
      success: false,
      error: error.message
    }
  }
}
```

---

## 6. 前端实现

### 6.1 项目结构

```
miniprogram/
├── app.js
├── app.json
├── app.wxss
├── pages/
│   ├── home/                # Markdown 转图片
│   │   ├── home.js
│   │   ├── home.json
│   │   ├── home.wxml
│   │   └── home.wxss
│   ├── digest/              # 书摘美化
│   │   ├── digest.js
│   │   ├── digest.json
│   │   ├── digest.wxml
│   │   └── digest.wxss
│   ├── preview/             # 图片预览和滤镜
│   │   ├── preview.js
│   │   ├── preview.json
│   │   ├── preview.wxml
│   │   └── preview.wxss
│   └── settings/            # 设置页面
│       └── ...
├── components/
│   ├── theme-picker/        # 主题选择器
│   ├── font-picker/         # 字体选择器
│   ├── size-picker/         # 尺寸选择器
│   └── markdown-preview/    # Markdown 预览
├── utils/
│   ├── storage.js           # 本地存储工具
│   ├── marked.min.js        # Markdown 解析
│   └── themes.js            # 主题配置
├── assets/
│   ├── icons/
│   └── backgrounds/         # 预置背景图
└── cloud/
    └── functions/           # 云函数
```

### 6.2 app.json 配置

```json
{
  "pages": [
    "pages/home/home",
    "pages/digest/digest",
    "pages/preview/preview",
    "pages/settings/settings"
  ],
  "window": {
    "backgroundTextStyle": "light",
    "navigationBarBackgroundColor": "#fff",
    "navigationBarTitleText": "玉桃文飨轩",
    "navigationBarTextStyle": "black"
  },
  "tabBar": {
    "color": "#999999",
    "selectedColor": "#1890ff",
    "list": [
      {
        "pagePath": "pages/home/home",
        "text": "Markdown",
        "iconPath": "assets/icons/markdown.png",
        "selectedIconPath": "assets/icons/markdown-active.png"
      },
      {
        "pagePath": "pages/digest/digest",
        "text": "书摘",
        "iconPath": "assets/icons/digest.png",
        "selectedIconPath": "assets/icons/digest-active.png"
      },
      {
        "pagePath": "pages/settings/settings",
        "text": "设置",
        "iconPath": "assets/icons/settings.png",
        "selectedIconPath": "assets/icons/settings-active.png"
      }
    ]
  },
  "cloud": true,
  "permission": {
    "scope.writePhotosAlbum": {
      "desc": "保存生成的图片到相册"
    }
  }
}
```

### 6.3 Home 页面完整实现

**home.wxml**：
```xml
<view class="page">
  <!-- 编辑区域 -->
  <view class="editor-section">
    <textarea
      class="editor"
      placeholder="输入 Markdown 内容..."
      value="{{content}}"
      bindinput="onContentChange"
      bindblur="onEditorBlur"
      auto-height
      maxlength="5000"
    />
  </view>

  <!-- 预览区域 -->
  <view class="preview-section">
    <scroll-view scroll-y class="preview-scroll">
      <view id="preview-container" class="preview-container {{theme}}-box">
        <view class="preview-content {{theme}}">
          <rich-text nodes="{{previewHtml}}" />
          <view wx:if="{{isWithDate}}" class="date-text">{{currentDate}}</view>
        </view>
      </view>
    </scroll-view>
  </view>

  <!-- 工具栏 -->
  <view class="toolbar">
    <view class="toolbar-row">
      <!-- 主题选择 -->
      <view class="toolbar-item">
        <text class="label">主题</text>
        <picker
          mode="selector"
          range="{{themes}}"
          range-key="name"
          value="{{themeIndex}}"
          bindchange="onThemeChange"
        >
          <view class="picker-value">{{themes[themeIndex].name}}</view>
        </picker>
      </view>

      <!-- 尺寸选择 -->
      <view class="toolbar-item">
        <text class="label">尺寸</text>
        <picker
          mode="selector"
          range="{{sizes}}"
          range-key="name"
          value="{{sizeIndex}}"
          bindchange="onSizeChange"
        >
          <view class="picker-value">{{sizes[sizeIndex].name}}</view>
        </picker>
      </view>

      <!-- 日期开关 -->
      <view class="toolbar-item">
        <text class="label">日期</text>
        <switch checked="{{isWithDate}}" bindchange="onDateToggle" />
      </view>
    </view>
  </view>

  <!-- 操作按钮 -->
  <view class="action-buttons">
    <button
      class="btn btn-primary"
      loading="{{isGenerating}}"
      disabled="{{isGenerating || !content}}"
      bindtap="generateImage"
    >
      {{isGenerating ? '生成中...' : '生成图片'}}
    </button>
  </view>
</view>
```

**home.js**：
```javascript
const { marked } = require('../../utils/marked.min.js')
const { THEMES, SIZES } = require('../../utils/themes.js')
const storage = require('../../utils/storage.js')

Page({
  data: {
    content: '',
    previewHtml: '',
    theme: 'note',
    themeIndex: 0,
    size: 'mobile',
    sizeIndex: 1,
    isWithDate: false,
    currentDate: '',
    isGenerating: false,
    themes: THEMES,
    sizes: SIZES
  },

  onLoad() {
    // 恢复上次内容
    const savedContent = storage.get('current-content') || ''
    const savedTheme = storage.get('current-theme') || 'note'
    const savedSize = storage.get('current-size') || 'mobile'
    const savedWithDate = storage.get('is-with-date') || false

    const themeIndex = THEMES.findIndex(t => t.id === savedTheme)
    const sizeIndex = SIZES.findIndex(s => s.id === savedSize)

    this.setData({
      content: savedContent,
      theme: savedTheme,
      themeIndex: themeIndex >= 0 ? themeIndex : 0,
      size: savedSize,
      sizeIndex: sizeIndex >= 0 ? sizeIndex : 1,
      isWithDate: savedWithDate,
      currentDate: this.getCurrentDate()
    })

    this.updatePreview()
  },

  // 内容变化
  onContentChange(e) {
    const content = e.detail.value
    this.setData({ content })
    this.updatePreview()
  },

  // 编辑器失焦时保存
  onEditorBlur() {
    storage.set('current-content', this.data.content)
  },

  // 更新预览
  updatePreview() {
    const html = marked.parse(this.data.content || '', { breaks: true })
    this.setData({ previewHtml: html })
  },

  // 主题切换
  onThemeChange(e) {
    const index = e.detail.value
    const theme = THEMES[index]
    this.setData({
      themeIndex: index,
      theme: theme.id
    })
    storage.set('current-theme', theme.id)
  },

  // 尺寸切换
  onSizeChange(e) {
    const index = e.detail.value
    const size = SIZES[index]
    this.setData({
      sizeIndex: index,
      size: size.id
    })
    storage.set('current-size', size.id)
  },

  // 日期开关
  onDateToggle(e) {
    const isWithDate = e.detail.value
    this.setData({
      isWithDate,
      currentDate: isWithDate ? this.getCurrentDate() : ''
    })
    storage.set('is-with-date', isWithDate)
  },

  // 获取当前日期
  getCurrentDate() {
    const date = new Date()
    const year = date.getFullYear()
    const month = String(date.getMonth() + 1).padStart(2, '0')
    const day = String(date.getDate()).padStart(2, '0')
    return `${year}-${month}-${day}`
  },

  // 生成图片
  async generateImage() {
    if (!this.data.content.trim()) {
      wx.showToast({ title: '请输入内容', icon: 'none' })
      return
    }

    this.setData({ isGenerating: true })

    try {
      const result = await wx.cloud.callFunction({
        name: 'renderImage',
        data: {
          type: 'markdown',
          content: this.data.content,
          theme: this.data.theme,
          size: this.data.size,
          isWithDate: this.data.isWithDate
        }
      })

      if (result.result.success) {
        // 跳转到预览页
        wx.navigateTo({
          url: `/pages/preview/preview?imageUrl=${encodeURIComponent(result.result.imageUrl)}&fileId=${encodeURIComponent(result.result.fileId)}`
        })
      } else {
        throw new Error(result.result.error)
      }
    } catch (error) {
      console.error('生成失败:', error)
      wx.showToast({ title: '生成失败，请重试', icon: 'none' })
    } finally {
      this.setData({ isGenerating: false })
    }
  },

  // 分享
  onShareAppMessage() {
    return {
      title: '玉桃文飨轩 - Markdown 转图片',
      path: '/pages/home/home'
    }
  }
})
```

**home.wxss**：
```css
.page {
  min-height: 100vh;
  background: #f5f5f5;
  padding-bottom: env(safe-area-inset-bottom);
}

.editor-section {
  padding: 20rpx;
}

.editor {
  width: 100%;
  min-height: 200rpx;
  padding: 20rpx;
  background: #fff;
  border-radius: 16rpx;
  font-size: 28rpx;
  line-height: 1.6;
}

.preview-section {
  padding: 20rpx;
}

.preview-scroll {
  max-height: 600rpx;
}

.preview-container {
  border-radius: 16rpx;
  overflow: hidden;
  box-shadow: 0 4rpx 20rpx rgba(0, 0, 0, 0.1);
}

.preview-content {
  padding: 40rpx;
  min-height: 300rpx;
}

.date-text {
  text-align: right;
  margin-top: 20rpx;
  font-size: 24rpx;
  color: #999;
}

/* 主题样式 */
.note-box {
  background: #fffcf5;
}
.note {
  border: 2rpx solid #e8e5dc;
}

.vitality-box {
  background: linear-gradient(225deg, #9cccfc 0, #e6cefd 99.54%);
}
.vitality {
  background: #f2f2f2;
  border-radius: 16rpx;
}

.dark-box {
  background: linear-gradient(to right, #434343 0%, black 100%);
}
.dark {
  color: #f2f2f2;
}

/* 其他主题... */

.toolbar {
  background: #fff;
  padding: 20rpx 30rpx;
  margin: 20rpx;
  border-radius: 16rpx;
}

.toolbar-row {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.toolbar-item {
  display: flex;
  flex-direction: column;
  align-items: center;
}

.label {
  font-size: 24rpx;
  color: #999;
  margin-bottom: 10rpx;
}

.picker-value {
  font-size: 28rpx;
  color: #333;
  padding: 10rpx 20rpx;
  background: #f5f5f5;
  border-radius: 8rpx;
}

.action-buttons {
  padding: 30rpx;
}

.btn {
  width: 100%;
  height: 88rpx;
  line-height: 88rpx;
  font-size: 32rpx;
  border-radius: 44rpx;
}

.btn-primary {
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  color: #fff;
}

.btn-primary[disabled] {
  background: #ccc;
}
```

### 6.4 Preview 页面（图片预览和滤镜）

**preview.wxml**：
```xml
<view class="page">
  <!-- 图片预览 -->
  <view class="image-container">
    <image
      class="preview-image"
      src="{{displayImageUrl}}"
      mode="widthFix"
      show-menu-by-longpress
    />
  </view>

  <!-- 滤镜选择 -->
  <view class="filter-section">
    <text class="section-title">选择滤镜</text>
    <scroll-view scroll-x class="filter-scroll">
      <view class="filter-list">
        <view
          wx:for="{{filters}}"
          wx:key="id"
          class="filter-item {{currentFilter === item.id ? 'active' : ''}}"
          bindtap="applyFilter"
          data-filter="{{item.id}}"
        >
          <view class="filter-preview {{item.id}}"></view>
          <text class="filter-name">{{item.name}}</text>
        </view>
      </view>
    </scroll-view>
  </view>

  <!-- 操作按钮 -->
  <view class="action-buttons">
    <button class="btn btn-outline" bindtap="saveToAlbum" loading="{{isSaving}}">
      保存到相册
    </button>
    <button class="btn btn-primary" open-type="share">
      分享给好友
    </button>
  </view>
</view>
```

**preview.js**：
```javascript
Page({
  data: {
    originalImageUrl: '',
    displayImageUrl: '',
    fileId: '',
    currentFilter: 'none',
    isSaving: false,
    isApplyingFilter: false,
    filters: [
      { id: 'none', name: '原图' },
      { id: 'grayscale', name: '黑白' },
      { id: 'sepia', name: '复古' },
      { id: 'vivid', name: '鲜艳' },
      { id: 'soft', name: '柔和' },
      { id: 'contrast', name: '对比' },
      { id: 'cool', name: '冷色' },
      { id: 'warm', name: '暖色' }
    ],
    filteredCache: {} // 缓存已处理的滤镜图片
  },

  onLoad(options) {
    const imageUrl = decodeURIComponent(options.imageUrl || '')
    const fileId = decodeURIComponent(options.fileId || '')

    this.setData({
      originalImageUrl: imageUrl,
      displayImageUrl: imageUrl,
      fileId: fileId
    })
  },

  // 应用滤镜
  async applyFilter(e) {
    const filterType = e.currentTarget.dataset.filter

    if (filterType === this.data.currentFilter) return
    if (this.data.isApplyingFilter) return

    // 原图
    if (filterType === 'none') {
      this.setData({
        displayImageUrl: this.data.originalImageUrl,
        currentFilter: 'none'
      })
      return
    }

    // 检查缓存
    if (this.data.filteredCache[filterType]) {
      this.setData({
        displayImageUrl: this.data.filteredCache[filterType],
        currentFilter: filterType
      })
      return
    }

    // 调用云函数处理
    this.setData({ isApplyingFilter: true })
    wx.showLoading({ title: '处理中...' })

    try {
      const result = await wx.cloud.callFunction({
        name: 'applyFilter',
        data: {
          imageFileId: this.data.fileId,
          filterType: filterType
        }
      })

      if (result.result.success) {
        // 缓存结果
        const cache = { ...this.data.filteredCache }
        cache[filterType] = result.result.imageUrl

        this.setData({
          displayImageUrl: result.result.imageUrl,
          currentFilter: filterType,
          filteredCache: cache
        })
      } else {
        throw new Error(result.result.error)
      }
    } catch (error) {
      console.error('滤镜处理失败:', error)
      wx.showToast({ title: '处理失败', icon: 'none' })
    } finally {
      this.setData({ isApplyingFilter: false })
      wx.hideLoading()
    }
  },

  // 保存到相册
  async saveToAlbum() {
    this.setData({ isSaving: true })

    try {
      // 下载图片
      const { tempFilePath } = await wx.downloadFile({
        url: this.data.displayImageUrl
      })

      // 保存到相册
      await wx.saveImageToPhotosAlbum({ filePath: tempFilePath })

      wx.showToast({ title: '已保存到相册', icon: 'success' })
    } catch (error) {
      if (error.errMsg?.includes('auth deny')) {
        // 引导用户授权
        wx.showModal({
          title: '需要授权',
          content: '请允许保存图片到相册',
          success: (res) => {
            if (res.confirm) {
              wx.openSetting()
            }
          }
        })
      } else {
        wx.showToast({ title: '保存失败', icon: 'none' })
      }
    } finally {
      this.setData({ isSaving: false })
    }
  },

  // 分享
  onShareAppMessage() {
    return {
      title: '我用玉桃文飨轩生成的图片',
      imageUrl: this.data.displayImageUrl,
      path: '/pages/home/home'
    }
  },

  onShareTimeline() {
    return {
      title: '玉桃文飨轩 - Markdown 转图片',
      imageUrl: this.data.displayImageUrl
    }
  }
})
```

---

## 7. 数据存储方案

### 7.1 本地存储（wx.storage）

```javascript
// utils/storage.js

const STORAGE_KEYS = {
  CONTENT: 'current-content',
  THEME: 'current-theme',
  SIZE: 'current-size',
  WITH_DATE: 'is-with-date',
  DIGEST_TEXT: 'digest-text',
  DIGEST_SETTINGS: 'digest-style-settings',
  DIGEST_LIST: 'digest-list'
}

const storage = {
  get(key) {
    try {
      const value = wx.getStorageSync(key)
      if (typeof value === 'string' && (value.startsWith('{') || value.startsWith('['))) {
        return JSON.parse(value)
      }
      return value
    } catch (e) {
      console.error('读取存储失败:', e)
      return null
    }
  },

  set(key, value) {
    try {
      const data = typeof value === 'object' ? JSON.stringify(value) : value
      wx.setStorageSync(key, data)
    } catch (e) {
      console.error('写入存储失败:', e)
    }
  },

  remove(key) {
    try {
      wx.removeStorageSync(key)
    } catch (e) {
      console.error('删除存储失败:', e)
    }
  },

  clear() {
    try {
      wx.clearStorageSync()
    } catch (e) {
      console.error('清空存储失败:', e)
    }
  }
}

module.exports = storage
```

### 7.2 云数据库（用户数据同步）

```javascript
// utils/db.js

const db = wx.cloud.database()

const collections = {
  users: db.collection('users'),
  digests: db.collection('digests'),
  settings: db.collection('settings')
}

const dbService = {
  // 保存用户设置（云端同步）
  async saveSettings(settings) {
    const { OPENID } = await this.getOpenId()

    const existing = await collections.settings
      .where({ _openid: OPENID })
      .get()

    if (existing.data.length > 0) {
      return collections.settings.doc(existing.data[0]._id).update({
        data: {
          ...settings,
          updatedAt: db.serverDate()
        }
      })
    } else {
      return collections.settings.add({
        data: {
          ...settings,
          createdAt: db.serverDate(),
          updatedAt: db.serverDate()
        }
      })
    }
  },

  // 获取用户设置
  async getSettings() {
    const { OPENID } = await this.getOpenId()

    const result = await collections.settings
      .where({ _openid: OPENID })
      .get()

    return result.data[0] || null
  },

  // 保存书摘
  async saveDigest(digest) {
    return collections.digests.add({
      data: {
        text: digest.text,
        hash: digest.hash,
        click: 0,
        createdAt: db.serverDate()
      }
    })
  },

  // 获取书摘列表
  async getDigests(page = 1, pageSize = 20) {
    const { OPENID } = await this.getOpenId()

    return collections.digests
      .where({ _openid: OPENID })
      .orderBy('createdAt', 'desc')
      .skip((page - 1) * pageSize)
      .limit(pageSize)
      .get()
  },

  // 获取 OpenID
  async getOpenId() {
    const result = await wx.cloud.callFunction({ name: 'getOpenId' })
    return result.result
  }
}

module.exports = dbService
```

---

## 8. 开发计划

### 8.1 阶段划分

| 阶段 | 内容 | 时间 | 交付物 |
|------|------|------|--------|
| **第 1 阶段** | 项目初始化 + 核心功能 | 2 周 | 可运行的 MVP |
| **第 2 阶段** | Digest 模式 + 主题系统 | 2 周 | 完整功能版 |
| **第 3 阶段** | 云函数 + 高级功能 | 2 周 | 云端渲染版 |
| **第 4 阶段** | 优化 + 测试 + 上线 | 2 周 | 正式版 |

### 8.2 第 1 阶段详细任务

**Week 1**：
- [ ] 创建小程序项目，配置云开发
- [ ] 实现 Home 页面基础 UI
- [ ] 集成 marked 库，实现 Markdown 预览
- [ ] 实现本地存储功能

**Week 2**：
- [ ] 实现主题选择器
- [ ] 实现尺寸选择器
- [ ] 部署 renderImage 云函数
- [ ] 实现图片生成和保存流程

### 8.3 第 2 阶段详细任务

**Week 3**：
- [ ] 实现 Digest 页面 UI
- [ ] 实现 Canvas 本地预览
- [ ] 实现字体、颜色、对齐等设置
- [ ] 实现背景图选择

**Week 4**：
- [ ] 完善 19 种主题样式
- [ ] 实现书摘历史记录
- [ ] 实现自定义背景上传
- [ ] 部署 uploadBackground 云函数

### 8.4 第 3 阶段详细任务

**Week 5**：
- [ ] 部署 applyFilter 云函数
- [ ] 实现滤镜预览页面
- [ ] 优化云函数性能（字体预加载）
- [ ] 实现云端字体渲染

**Week 6**：
- [ ] 实现用户设置云端同步
- [ ] 实现分享功能
- [ ] 添加使用统计
- [ ] 性能优化（图片压缩、缓存）

### 8.5 第 4 阶段详细任务

**Week 7**：
- [ ] 全面测试（功能、兼容性、性能）
- [ ] Bug 修复
- [ ] UI/UX 优化
- [ ] 准备上线材料（截图、描述）

**Week 8**：
- [ ] 提交审核
- [ ] 处理审核反馈
- [ ] 正式发布
- [ ] 监控和反馈收集

---

## 9. 注意事项

### 9.1 云函数限制

| 限制项 | 值 | 应对方案 |
|-------|-----|---------|
| 执行时长 | 60 秒 | 优化渲染速度，预加载资源 |
| 内存 | 256MB-1GB | 选择合适规格，控制图片尺寸 |
| 代码包大小 | 50MB | Puppeteer 使用 @sparticuz/chromium |
| 并发数 | 1000 | 添加队列机制，限流 |

### 9.2 小程序审核要点

1. **用户隐私**：明确说明数据本地处理
2. **内容安全**：添加敏感词过滤
3. **功能完整**：确保所有功能可用
4. **UI 规范**：遵循小程序设计规范

### 9.3 性能优化建议

1. **图片缓存**：已生成的图片缓存到本地
2. **预加载**：字体和背景图预加载
3. **懒加载**：主题样式按需加载
4. **压缩**：上传前压缩图片

### 9.4 成本估算

| 资源 | 免费额度 | 超出费用 |
|------|---------|---------|
| 云函数调用 | 100 万次/月 | 0.0133 元/万次 |
| 云存储 | 5GB | 0.0043 元/GB/天 |
| 云数据库 | 2GB | 0.07 元/GB/天 |
| CDN 流量 | 5GB/月 | 0.18 元/GB |

**预估月成本**（1000 DAU）：约 10-30 元

---

## 附录

### A. 参考资源

- [微信小程序文档](https://developers.weixin.qq.com/miniprogram/dev/framework/)
- [微信云开发文档](https://developers.weixin.qq.com/miniprogram/dev/wxcloud/basis/getting-started.html)
- [Puppeteer 文档](https://pptr.dev/)
- [Sharp 文档](https://sharp.pixelplumbing.com/)

### B. 相关项目

- [wechat-miniprogram-canvas](https://github.com/nicexixi/wechat-miniprogram-canvas)
- [mp-html](https://github.com/nicexixi/mp-html) - 小程序富文本组件

### C. 常见问题

**Q: 云函数超时怎么办？**
A: 1) 优化代码减少执行时间；2) 拆分为多个云函数；3) 使用云托管（无超时限制）

**Q: 字体加载失败怎么办？**
A: 1) 使用 CDN 加速字体文件；2) 字体文件转 base64 内嵌；3) 降级使用系统字体

**Q: 图片生成模糊怎么办？**
A: 1) 提高 deviceScaleFactor；2) 使用更大的 viewport；3) 输出 2x/3x 分辨率
