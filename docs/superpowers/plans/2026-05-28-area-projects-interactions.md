# AreaProjects 原型交互补齐 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 AreaProjects HTML 原型补齐关键交互层（右键菜单、CRUD mock、Tab 管理、KB 筛选、添加项目弹窗等），使其达到 5/5 可开发标准

**Architecture:** 除 `closeTab` 挂载全局作用域供 inline handler 调用外，其余交互均在 `initAreaProjects()` IIFE 内用 DOM mock 实现，不涉及真实文件 I/O。右键菜单采用事件委托（单一 contextmenu 监听器 on `#areas-sidebar`，按 `closest()` 分派），确保动态创建的节点自动获得菜单。CRUD 操作直接操作 DOM + areaFiles 数据对象。复用已有的 `openFile()`/`toggleFolder()`/`switchToEditor()`/`switchToKB()` 函数。新功能按职责分组添加到对应注释块。

**Tech Stack:** Vanilla JS, HTML prototype

---

### Task 1: 快速修正——_reports 角标 + 终端/Agent 占位标注

**Files:**
- Modify: `docs/fp-ui/00-layout-prototype.html` — 侧边栏 _reports 行 + 辅助栏面板

- [ ] **Step 1: 移除 _reports 角标**

规格 §2.5 明确 `_reports/` 无角标。找到两处 _reports 行，移除 `<span class="count">` 元素：

1. FocusPilot 项目的 `data-area-id="fp-rpt"` 行（约 1142-1144 行）：删除 `<span class="count">2</span>`
2. 大客户跟踪的 `data-area-id="client-rpt"` 行（约 1199-1201 行）：删除 `<span class="count">1</span>`

注意：分布式系统笔记没有 _reports 文件夹，不需要处理。

- [ ] **Step 2: 终端面板添加占位标注**

在终端面板（`id="areas-aux-terminal"`）底部追加一行灰色提示文字：

找到终端面板闭合标签 `</div>` 前（光标闪烁行 `<span style="display:inline-block;width:6px..."` 之后），添加：

```html
<br><br><span style="color:var(--dim);font-size:10px;font-style:italic">💡 终端预览（开发时接入真实 PTY）</span>
```

- [ ] **Step 3: Agent 面板输入框添加占位标注**

找到 Agent 面板的发送按钮行（`<button class="btn primary"...>发送</button>`），将其 `onclick` 改为显示 toast 提示。在 `initAreaProjects()` 内添加：

```javascript
// ── Agent 发送按钮占位提示 ──
var agentSendBtn = document.querySelector('#areas-aux-agent .btn.primary');
if (agentSendBtn) {
  agentSendBtn.addEventListener('click', function() {
    showAreaToast('Agent 对话为预览占位，开发时接入真实 Agent');
  });
}
```

同时在 `initAreaProjects()` 顶部（`var currentFile = 'arch';` 之后）添加通用 toast 函数：

```javascript
// ── 通用 toast 提示 ──
function showAreaToast(msg) {
  var old = document.getElementById('areas-toast');
  if (old) old.remove();
  var toast = document.createElement('div');
  toast.id = 'areas-toast';
  toast.style.cssText = 'position:fixed;bottom:24px;left:50%;transform:translateX(-50%);background:var(--surface-2);border:1px solid var(--line);border-radius:var(--radius);padding:8px 16px;font-size:12px;color:var(--text);z-index:999;box-shadow:0 4px 12px rgba(0,0,0,.3);transition:opacity .3s';
  toast.textContent = msg;
  document.body.appendChild(toast);
  setTimeout(function() { toast.style.opacity = '0'; setTimeout(function() { toast.remove(); }, 300); }, 3000);
}
```

- [ ] **Step 4: 验证**

浏览器打开原型 → AreaProjects 页面：
1. _reports 文件夹无数字角标 ✓
2. 终端面板底部显示"终端预览"提示 ✓
3. Agent 面板点击"发送" → 底部 toast 提示 ✓

- [ ] **Step 5: 提交**

```bash
git add docs/fp-ui/00-layout-prototype.html
git commit -m "fix(fp-ui): AreaProjects _reports 角标移除 + 终端/Agent 占位标注"
```

---

### Task 2: 右键菜单系统 + Mock CRUD 操作

**Files:**
- Modify: `docs/fp-ui/00-layout-prototype.html` — `<style>` 区 + `initAreaProjects()` 内 JS

- [ ] **Step 1: 添加右键菜单 + 工具类 CSS**

在 `</style>` 闭合标签前添加菜单样式和工具类：

```css
.area-ctx-menu { position:fixed;z-index:200;background:var(--surface-2);border:1px solid var(--line);border-radius:8px;padding:4px 0;min-width:180px;box-shadow:0 8px 24px rgba(0,0,0,.4);font-size:12px; }
.area-ctx-item { display:flex;align-items:center;gap:8px;padding:6px 14px;cursor:pointer;color:var(--text); }
.area-ctx-item:hover { background:rgba(82,156,202,0.12); }
.area-ctx-item.danger { color:var(--red); }
.area-ctx-item.danger:hover { background:rgba(248,113,113,0.12); }
.area-ctx-sep { height:1px;background:var(--line-soft);margin:4px 0; }
.area-hidden { display:none !important; }
```

- [ ] **Step 2: 添加右键菜单 JS 基础设施**

在 `initAreaProjects()` 内 `showAreaToast` 函数之后添加：

```javascript
// ── 右键菜单系统 ──
var ctxMenu = null;

function showContextMenu(e, items) {
  e.preventDefault();
  e.stopPropagation();
  hideContextMenu();
  ctxMenu = document.createElement('div');
  ctxMenu.className = 'area-ctx-menu';
  items.forEach(function(item) {
    if (item === '---') {
      var sep = document.createElement('div');
      sep.className = 'area-ctx-sep';
      ctxMenu.appendChild(sep);
      return;
    }
    var row = document.createElement('div');
    row.className = 'area-ctx-item' + (item.danger ? ' danger' : '');
    row.innerHTML = '<span style="width:16px;text-align:center;flex-shrink:0">' + item.icon + '</span><span>' + item.label + '</span>';
    row.addEventListener('click', function() { hideContextMenu(); if (item.action) item.action(); });
    ctxMenu.appendChild(row);
  });
  ctxMenu.style.left = Math.min(e.clientX, window.innerWidth - 200) + 'px';
  ctxMenu.style.top = Math.min(e.clientY, window.innerHeight - items.length * 32) + 'px';
  document.body.appendChild(ctxMenu);
}

function hideContextMenu() {
  if (ctxMenu) { ctxMenu.remove(); ctxMenu = null; }
}

document.addEventListener('click', hideContextMenu);
document.addEventListener('contextmenu', function(e) {
  if (!e.target.closest('#areas-sidebar')) hideContextMenu();
});
```

- [ ] **Step 3: 侧边栏 .area-name 注入**

为了让重命名功能能精确定位名称文本（不误改图标/箭头），在 `initAreaProjects()` 内菜单基础设施代码之后，给所有侧边栏节点注入 `.area-name` 标记：

```javascript
// ── 侧边栏名称标记（供重命名精确定位）──
document.querySelectorAll('#areas-sidebar .area-file > span').forEach(function(span) {
  if (span.querySelector('.area-name')) return;
  var html = span.innerHTML.trim();
  var idx = html.indexOf(' ');
  if (idx > 0) {
    span.innerHTML = html.substring(0, idx + 1) + '<span class="area-name">' + html.substring(idx + 1) + '</span>';
  }
});
document.querySelectorAll('#areas-sidebar .area-folder > span, #areas-sidebar .area-project > span').forEach(function(span) {
  if (span.querySelector('.area-name') || !span.querySelector('.area-arrow')) return;
  var arrow = span.querySelector('.area-arrow');
  var textNode = arrow.nextSibling;
  if (textNode && textNode.nodeType === 3) {
    var match = textNode.textContent.match(/^(\s*.+?\s)(\S.*)$/);
    if (match) {
      textNode.textContent = match[1];
      var nameSpan = document.createElement('span');
      nameSpan.className = 'area-name';
      nameSpan.textContent = match[2];
      span.insertBefore(nameSpan, textNode.nextSibling);
    }
  }
});
```

- [ ] **Step 4: Mock CRUD 函数**

在 .area-name 注入代码之后添加所有 CRUD 函数（必须在菜单绑定之前定义，确保每个提交都不会报错）：

```javascript
// ── Mock CRUD 操作 ──
var mockCounter = 0;

function createMockFile(parentEl) {
  mockCounter++;
  var areaId = parentEl.dataset.areaId;
  var children = document.querySelector('.area-children[data-area-parent="' + areaId + '"]');
  if (!children) return;
  children.classList.remove('collapsed');
  var arrow = parentEl.querySelector('.area-arrow');
  if (arrow) arrow.textContent = '▾';
  var fileKey = 'mock-file-' + mockCounter;
  var isKb = parentEl.classList.contains('area-kb-folder');
  var fileName = isKb ? '新卡片 ' + mockCounter + '.md' : '新文件 ' + mockCounter + '.md';
  var icon = isKb ? '🧠' : '📄';
  areaFiles[fileKey] = { name: fileName, path: parentEl.textContent.trim().replace(/^[▾▸]\s*/, ''), content: '<h1 style="font-size:22px;font-weight:700;margin:0 0 12px">' + fileName + '</h1><p style="color:var(--muted)">新建文件，等待编辑...</p>' };
  var newEl = document.createElement('div');
  newEl.className = 'side-item indent area-file' + (isKb ? ' area-kb-file' : '');
  newEl.dataset.areaFile = fileKey;
  newEl.style.paddingLeft = '36px';
  var span = document.createElement('span');
  span.textContent = icon + ' ';
  var nameSpan = document.createElement('span');
  nameSpan.className = 'area-name';
  nameSpan.textContent = fileName;
  span.appendChild(nameSpan);
  newEl.appendChild(span);
  newEl.addEventListener('click', function(e) { e.stopPropagation(); openFile(fileKey); });
  children.appendChild(newEl);
  openFile(fileKey);
  showAreaToast('已创建 ' + fileName);
}

function createMockFolder(parentEl) {
  mockCounter++;
  var areaId = parentEl.dataset.areaId;
  var children = document.querySelector('.area-children[data-area-parent="' + areaId + '"]');
  if (!children) return;
  children.classList.remove('collapsed');
  var arrow = parentEl.querySelector('.area-arrow');
  if (arrow) arrow.textContent = '▾';
  var folderId = 'mock-folder-' + mockCounter;
  var folderName = '新文件夹 ' + mockCounter;
  var folderEl = document.createElement('div');
  folderEl.className = 'side-item indent area-folder';
  folderEl.dataset.areaId = folderId;
  folderEl.style.cssText = 'cursor:pointer;padding-left:36px';
  var fSpan = document.createElement('span');
  var fArrow = document.createElement('span');
  fArrow.className = 'area-arrow';
  fArrow.textContent = '▸';
  fSpan.appendChild(fArrow);
  fSpan.appendChild(document.createTextNode(' 📂 '));
  var fName = document.createElement('span');
  fName.className = 'area-name';
  fName.textContent = folderName;
  fSpan.appendChild(fName);
  folderEl.appendChild(fSpan);
  var folderChildren = document.createElement('div');
  folderChildren.className = 'area-children collapsed';
  folderChildren.dataset.areaParent = folderId;
  children.appendChild(folderEl);
  children.appendChild(folderChildren);
  folderEl.addEventListener('click', function(e) { if (e.target.closest('.area-file')) return; e.stopPropagation(); toggleFolder(this); });
  showAreaToast('已创建文件夹 ' + folderName);
}

function deleteFileNode(el, fileKey) {
  var openTab = document.querySelector('.areas-tab[data-area-file="' + fileKey + '"]');
  if (openTab && typeof closeTab === 'function') closeTab(openTab);
  else if (openTab) openTab.remove();
  el.style.transition = 'opacity .2s';
  el.style.opacity = '0';
  setTimeout(function() { el.remove(); }, 200);
  if (areaFiles[fileKey]) delete areaFiles[fileKey];
  showAreaToast('已删除');
}

function deleteFolderNode(el) {
  var areaId = el.dataset.areaId;
  var children = document.querySelector('.area-children[data-area-parent="' + areaId + '"]');
  var count = children ? children.querySelectorAll('.area-file').length : 0;
  if (count > 0 && !confirm('文件夹内有 ' + count + ' 个文件，确定删除？')) return;
  if (children) children.remove();
  el.style.transition = 'opacity .2s';
  el.style.opacity = '0';
  setTimeout(function() { el.remove(); }, 200);
  showAreaToast('已删除文件夹');
}

function removeProject(el) {
  var areaId = el.dataset.areaId;
  if (!confirm('移除项目后文件仍保留在磁盘，确定移除？')) return;
  var children = document.querySelector('.area-children[data-area-parent="' + areaId + '"]');
  if (children) children.remove();
  el.style.transition = 'opacity .2s';
  el.style.opacity = '0';
  setTimeout(function() { el.remove(); }, 200);
  showAreaToast('已移除项目');
}

function startRename(el) {
  var nameSpan = el.querySelector('.area-name');
  if (!nameSpan) return;
  var isPipeline = /_(materials|reports|kb)/.test(el.textContent);
  if (isPipeline) { showAreaToast('知识管道文件夹不允许重命名'); return; }
  var oldName = nameSpan.textContent.trim();
  var cancelled = false;
  var input = document.createElement('input');
  input.type = 'text';
  input.value = oldName;
  input.style.cssText = 'background:var(--bg);border:1px solid var(--accent);border-radius:3px;color:var(--text);font-size:12px;padding:1px 4px;width:120px;outline:none;';
  nameSpan.textContent = '';
  nameSpan.appendChild(input);
  input.focus();
  input.select();
  function finish() {
    if (cancelled) return;
    var newName = input.value.trim() || oldName;
    nameSpan.textContent = newName;
    var fileKey = el.dataset.areaFile;
    if (fileKey && areaFiles[fileKey]) areaFiles[fileKey].name = newName;
  }
  input.addEventListener('keydown', function(e) {
    if (e.key === 'Enter') { e.preventDefault(); finish(); }
    if (e.key === 'Escape') { cancelled = true; nameSpan.textContent = oldName; input.blur(); }
  });
  input.addEventListener('blur', finish);
}
```

- [ ] **Step 5: 事件委托绑定右键菜单**

使用事件委托代替逐节点绑定，确保动态创建的节点也自动拥有右键菜单：

```javascript
// ── 右键菜单事件委托 ──
document.querySelector('#areas-sidebar').addEventListener('contextmenu', function(e) {
  var el;

  // ── 文件右键（优先匹配最内层） ──
  el = e.target.closest('.area-file');
  if (el) {
    var isKb = el.classList.contains('area-kb-file');
    var fileKey = el.dataset.areaFile;
    var file = areaFiles[fileKey];
    if (isKb) {
      showContextMenu(e, [
        { icon: '✏️', label: '重命名', action: function() { startRename(el); } },
        { icon: '📋', label: '复制路径', action: function() { showAreaToast('已复制: ' + (file ? file.path + '/' + file.name : fileKey)); } }
      ]);
    } else {
      showContextMenu(e, [
        { icon: '✏️', label: '重命名', action: function() { startRename(el); } },
        { icon: '📁', label: '移动到...', action: function() { showAreaToast('移动到... (开发时实现)'); } },
        { icon: '📋', label: '复制路径', action: function() { showAreaToast('已复制: ' + (file ? file.path + '/' + file.name : fileKey)); } },
        { icon: '📂', label: '在 Finder 中显示', action: function() { showAreaToast('在 Finder 中显示 (开发时实现)'); } },
        '---',
        { icon: '🗑', label: '删除', danger: true, action: function() { deleteFileNode(el, fileKey); } }
      ]);
    }
    return;
  }

  // ── 文件夹右键 ──
  el = e.target.closest('.area-folder');
  if (el) {
    var isKb = el.classList.contains('area-kb-folder');
    var text = el.textContent;
    var isReports = text.indexOf('_reports') !== -1;
    var isMaterials = text.indexOf('_materials') !== -1;

    if (isKb) {
      showContextMenu(e, [
        { icon: '📄', label: '新建卡片', action: function() { createMockFile(el); } },
        { icon: '📂', label: '在 Finder 中显示', action: function() { showAreaToast('在 Finder 中显示 (开发时实现)'); } }
      ]);
    } else if (isMaterials) {
      showContextMenu(e, [
        { icon: '📄', label: '新建文件', action: function() { createMockFile(el); } },
        { icon: '📂', label: '在 Finder 中显示', action: function() { showAreaToast('在 Finder 中显示 (开发时实现)'); } },
        '---',
        { icon: '🔄', label: '同步整合', action: function() { showAreaToast('🔄 正在整合素材... (Pipeline 开发时实现)'); } }
      ]);
    } else if (isReports) {
      showContextMenu(e, [
        { icon: '📄', label: '新建文件', action: function() { createMockFile(el); } },
        { icon: '📂', label: '在 Finder 中显示', action: function() { showAreaToast('在 Finder 中显示 (开发时实现)'); } }
      ]);
    } else {
      showContextMenu(e, [
        { icon: '📄', label: '新建文件', action: function() { createMockFile(el); } },
        { icon: '📁', label: '新建文件夹', action: function() { createMockFolder(el); } },
        '---',
        { icon: '✏️', label: '重命名', action: function() { startRename(el); } },
        { icon: '📁', label: '移动到...', action: function() { showAreaToast('移动到... (开发时实现)'); } },
        { icon: '📋', label: '复制路径', action: function() { showAreaToast('已复制路径'); } },
        { icon: '📂', label: '在 Finder 中显示', action: function() { showAreaToast('在 Finder 中显示 (开发时实现)'); } },
        '---',
        { icon: '🗑', label: '删除', danger: true, action: function() { deleteFolderNode(el); } }
      ]);
    }
    return;
  }

  // ── 项目右键 ──
  el = e.target.closest('.area-project');
  if (el) {
    var isFav = el.dataset.areaFav === 'true';
    showContextMenu(e, [
      { icon: '📄', label: '新建文件', action: function() { createMockFile(el); } },
      { icon: '📁', label: '新建文件夹', action: function() { createMockFolder(el); } },
      '---',
      { icon: '📌', label: '置顶项目', action: function() { showAreaToast('已置顶'); } },
      { icon: '✏️', label: '重命名项目', action: function() { startRename(el); } },
      { icon: '⭐', label: isFav ? '取消收藏' : '收藏', action: function() { el.dataset.areaFav = isFav ? '' : 'true'; showAreaToast(isFav ? '已取消收藏' : '已收藏'); } },
      { icon: '📂', label: '在 Finder 中显示', action: function() { showAreaToast('在 Finder 中显示 (开发时实现)'); } },
      { icon: '💻', label: '在 Studio 中打开', action: function() { showAreaToast('在 Studio 中打开 (开发时实现)'); } },
      '---',
      { icon: '🗑', label: '移除项目', danger: true, action: function() { removeProject(el); } }
    ]);
    return;
  }
});
```

- [ ] **Step 6: 工具栏按钮绑定**

找到工具栏三个按钮（📁 📄 ⭐），添加 id 和事件绑定。

在 HTML 中给工具栏按钮添加 id：
- `title="新建文件夹"` 的按钮添加 `id="areas-btn-newfolder"`
- `title="新建文件"` 的按钮添加 `id="areas-btn-newfile"`
- `title="收藏筛选"` 的按钮添加 `id="areas-btn-fav"`

在 JS 中添加绑定：

```javascript
// ── 工具栏按钮 ──
var btnNewFolder = $('areas-btn-newfolder');
var btnNewFile = $('areas-btn-newfile');
var btnFav = $('areas-btn-fav');

function getSelectedProject() {
  var active = document.querySelector('#areas-sidebar .area-file.active');
  if (active) {
    var parent = active.closest('.area-children');
    if (parent) {
      var projId = parent.dataset.areaParent;
      return document.querySelector('#areas-sidebar .area-project[data-area-id="' + projId + '"]') ||
             document.querySelector('#areas-sidebar [data-area-id="' + projId + '"]');
    }
  }
  return document.querySelector('#areas-sidebar .area-project.active') ||
         document.querySelector('#areas-sidebar .area-project');
}

if (btnNewFolder) btnNewFolder.addEventListener('click', function(e) {
  e.stopPropagation();
  var proj = getSelectedProject();
  if (proj) createMockFolder(proj);
  else showAreaToast('请先选择一个项目');
});

if (btnNewFile) btnNewFile.addEventListener('click', function(e) {
  e.stopPropagation();
  var proj = getSelectedProject();
  if (proj) createMockFile(proj);
  else showAreaToast('请先选择一个项目');
});

var favMode = false;
if (btnFav) btnFav.addEventListener('click', function(e) {
  e.stopPropagation();
  favMode = !favMode;
  this.style.color = favMode ? 'var(--amber)' : 'var(--dim)';
  document.querySelectorAll('#areas-sidebar .area-project').forEach(function(p) {
    if (favMode && p.dataset.areaFav !== 'true') {
      p.style.display = 'none';
      var ch = document.querySelector('.area-children[data-area-parent="' + p.dataset.areaId + '"]');
      if (ch) ch.style.display = 'none';
    } else {
      p.style.display = '';
      var ch = document.querySelector('.area-children[data-area-parent="' + p.dataset.areaId + '"]');
      if (ch) ch.style.display = '';
    }
  });
  showAreaToast(favMode ? '仅显示收藏项目' : '显示全部项目');
});
```

- [ ] **Step 7: 验证右键菜单 + CRUD**

浏览器打开原型：
1. 右键普通文件（架构设计.md）→ 6 项菜单（重命名、移动、复制路径、Finder、分隔线、删除） ✓
2. 右键文件夹（参考资料）→ 8 项菜单（新建文件、新建文件夹、分隔线、重命名…删除） ✓
3. 右键 _materials → 4 项菜单（新建文件、Finder、分隔线、同步整合） ✓
4. 右键 _kb → 2 项菜单（新建卡片、Finder） ✓
5. 右键项目（FocusPilot）→ 9 项菜单 ✓
6. 点击空白处 → 菜单消失 ✓
7. 右键项目 → "新建文件" → 文件出现 + 编辑器打开 ✓
8. 工具栏 📄 → 在当前活动项目下创建文件 ✓
9. 工具栏 📁 → 创建文件夹 ✓
10. 右键文件 → "删除" → 文件消失 + toast"已删除" ✓
11. 右键文件 → "重命名" → 内联输入框 → Enter 确认 ✓
12. 右键 _materials → "重命名" → "知识管道文件夹不允许重命名" toast ✓
13. **新建文件后右键该文件** → 菜单正常弹出（事件委托验证） ✓
14. 右键项目 → "收藏" → 工具栏 ⭐ → 仅显示已收藏 ✓
15. 右键项目 → "移除项目" → 确认后项目消失 ✓

- [ ] **Step 8: 提交**

```bash
git add docs/fp-ui/00-layout-prototype.html
git commit -m "feat(fp-ui): AreaProjects 右键菜单（事件委托）+ Mock CRUD + 工具栏绑定"
```

---

### Task 3: Tab 管理（关闭按钮 + 动态 Tab + 空状态）

**Files:**
- Modify: `docs/fp-ui/00-layout-prototype.html` — Tab 条 HTML + 编辑器容器 + `initAreaProjects()` JS

- [ ] **Step 1: 给编辑器关键容器添加稳定 ID**

为避免用 `style*=` 选择器（脆弱），给编辑器区域的三个关键容器添加 id。找到以下元素并添加 id：

1. **面包屑行**：找到 Tab 条（`id="areas-tab-bar"`）之后的 `<div style="display:flex;align-items:center;padding:8px...">` 容器（包含 `id="areas-breadcrumb"` 的 span），添加 `id="areas-breadcrumb-row"`
2. **内容区**：找到面包屑行之后的 `<div style="flex:1;min-height:0;overflow:auto...">` 容器（包含编辑器预览内容），添加 `id="areas-content"`

- [ ] **Step 2: 给现有 Tab 添加关闭按钮 HTML**

找到 `id="areas-tab-bar"` 内的两个 `.areas-tab` div，给每个 Tab 内容末尾添加关闭按钮：

第一个 Tab（arch）改为：
```html
<div class="areas-tab active" data-area-file="arch" style="display:flex;align-items:center;gap:6px;padding:6px 14px;font-size:12px;cursor:pointer;border-bottom:2px solid var(--accent);color:var(--text);margin-bottom:-1px"><span class="tab-name">📄 架构设计.md</span><span class="tab-close" style="font-size:10px;color:var(--dim);margin-left:4px;cursor:pointer;padding:0 2px;border-radius:2px" onmouseover="this.style.color='var(--red)'" onmouseout="this.style.color='var(--dim)'" onclick="event.stopPropagation();closeTab(this.parentElement)">✕</span></div>
```

第二个 Tab（tech）同理：
```html
<div class="areas-tab" data-area-file="tech" style="display:flex;align-items:center;gap:6px;padding:6px 14px;font-size:12px;cursor:pointer;border-bottom:2px solid transparent;color:var(--dim);margin-bottom:-1px"><span class="tab-name">📄 技术选型.md</span><span class="tab-close" style="font-size:10px;color:var(--dim);margin-left:4px;cursor:pointer;padding:0 2px;border-radius:2px" onmouseover="this.style.color='var(--red)'" onmouseout="this.style.color='var(--dim)'" onclick="event.stopPropagation();closeTab(this.parentElement)">✕</span></div>
```

- [ ] **Step 3: 添加空状态 HTML**

在 `id="areas-tab-bar"` 同级、面包屑行（`id="areas-breadcrumb-row"`）之前，添加空状态占位（默认隐藏）：

```html
<div id="areas-empty-state" style="display:none;flex:1;flex-direction:column;align-items:center;justify-content:center;gap:12px;color:var(--dim);min-height:0">
  <span style="font-size:36px">📄</span>
  <span style="font-size:14px;font-weight:500">没有打开的文件</span>
  <span style="font-size:12px">从侧边栏选择文件打开</span>
</div>
```

- [ ] **Step 4: 重写 openFile 的 Tab 逻辑**

将 `openFile` 中 Tab 条更新部分（从 `// 更新 Tab 条` 到 Tab 闭合 `}`）替换为使用稳定 ID 的版本：

```javascript
// 更新 Tab 条
var tabBar = $('areas-tab-bar');
if (tabBar) {
  var emptyState = $('areas-empty-state');
  if (emptyState) emptyState.style.display = 'none';
  var breadcrumbRow = $('areas-breadcrumb-row');
  if (breadcrumbRow) breadcrumbRow.classList.remove('area-hidden');
  var contentArea = $('areas-content');
  if (contentArea) contentArea.classList.remove('area-hidden');

  var tabs = tabBar.querySelectorAll('.areas-tab');
  var found = false;
  tabs.forEach(function(t) {
    var isActive = t.dataset.areaFile === fileKey;
    t.classList.toggle('active', isActive);
    t.style.borderBottomColor = isActive ? 'var(--accent)' : 'transparent';
    t.style.color = isActive ? 'var(--text)' : 'var(--dim)';
    if (isActive) found = true;
  });
  if (!found) {
    var newTab = document.createElement('div');
    newTab.className = 'areas-tab active';
    newTab.dataset.areaFile = fileKey;
    newTab.style.cssText = 'display:flex;align-items:center;gap:6px;padding:6px 14px;font-size:12px;cursor:pointer;border-bottom:2px solid var(--accent);color:var(--text);margin-bottom:-1px';
    var tabName = document.createElement('span');
    tabName.className = 'tab-name';
    tabName.textContent = '📄 ' + file.name;
    newTab.appendChild(tabName);
    var tabClose = document.createElement('span');
    tabClose.className = 'tab-close';
    tabClose.style.cssText = 'font-size:10px;color:var(--dim);margin-left:4px;cursor:pointer;padding:0 2px;border-radius:2px';
    tabClose.textContent = '✕';
    tabClose.onmouseover = function() { this.style.color = 'var(--red)'; };
    tabClose.onmouseout = function() { this.style.color = 'var(--dim)'; };
    tabClose.onclick = function(ev) { ev.stopPropagation(); closeTab(newTab); };
    newTab.appendChild(tabClose);
    newTab.addEventListener('click', function() { if (this.dataset.areaFile) openFile(this.dataset.areaFile); });
    tabs.forEach(function(t) {
      t.classList.remove('active');
      t.style.borderBottomColor = 'transparent';
      t.style.color = 'var(--dim)';
    });
    tabBar.appendChild(newTab);
  }
}
```

- [ ] **Step 5: 添加 closeTab 全局函数**

`closeTab` 必须在全局作用域（inline onclick 需要）。在 `</script>` 前、`initAreaProjects()` IIFE 之后添加：

```javascript
function closeTab(tabEl) {
  var tabBar = document.getElementById('areas-tab-bar');
  if (!tabBar) return;
  var wasActive = tabEl.classList.contains('active');
  tabEl.remove();
  var remaining = tabBar.querySelectorAll('.areas-tab');
  if (remaining.length === 0) {
    var emptyState = document.getElementById('areas-empty-state');
    if (emptyState) emptyState.style.display = 'flex';
    var breadcrumbRow = document.getElementById('areas-breadcrumb-row');
    if (breadcrumbRow) breadcrumbRow.classList.add('area-hidden');
    var contentArea = document.getElementById('areas-content');
    if (contentArea) contentArea.classList.add('area-hidden');
  } else if (wasActive) {
    var last = remaining[remaining.length - 1];
    last.classList.add('active');
    last.style.borderBottomColor = 'var(--accent)';
    last.style.color = 'var(--text)';
    if (last.dataset.areaFile) {
      var openFileFn = document.querySelector('#areas-sidebar .area-file[data-area-file="' + last.dataset.areaFile + '"]');
      if (openFileFn) openFileFn.click();
    }
  }
}
```

- [ ] **Step 6: 验证 Tab 管理**

1. 点击侧边栏文件 → Tab 条新增 Tab ✓
2. 点击 Tab 上 ✕ → Tab 关闭 ✓
3. 关闭活动 Tab → 切到最后一个 Tab ✓
4. 关闭所有 Tab → 显示空状态（面包屑和内容区隐藏） ✓
5. 空状态下点击侧边栏文件 → 恢复编辑器 + 新 Tab ✓

- [ ] **Step 7: 提交**

```bash
git add docs/fp-ui/00-layout-prototype.html
git commit -m "feat(fp-ui): AreaProjects Tab 管理——关闭按钮 + 动态新增 + 空状态"
```

---

### Task 4: 添加项目弹窗

**Files:**
- Modify: `docs/fp-ui/00-layout-prototype.html` — AreaProjects section HTML + `initAreaProjects()` JS

- [ ] **Step 1: 添加弹窗 HTML**

在 AreaProjects `</section>` 闭合标签前（`id="areas-kb"` div 之后）添加。注意路径行有 `id="areas-proj-path-row"` 用于 radio 切换可见性：

```html
<!-- ═══ AreaProjects: 添加项目弹窗 ═══ -->
<div id="areas-add-project-modal" style="position:fixed;inset:0;background:rgba(0,0,0,.5);z-index:60;display:none;align-items:center;justify-content:center;backdrop-filter:blur(4px)">
  <div style="width:440px;max-width:90vw;background:var(--surface);border:1px solid var(--line);border-radius:12px;box-shadow:0 8px 32px rgba(0,0,0,.5);padding:24px" onclick="event.stopPropagation()">
    <h3 style="font-size:16px;font-weight:600;margin:0 0 16px">添加项目</h3>
    <div style="margin-bottom:14px">
      <div style="font-size:12px;font-weight:500;margin-bottom:6px;color:var(--muted)">项目类型</div>
      <label style="font-size:12px;cursor:pointer;margin-right:16px"><input type="radio" name="areas-proj-type" value="local" checked style="margin-right:4px">指向本地目录</label>
      <label style="font-size:12px;cursor:pointer"><input type="radio" name="areas-proj-type" value="new" style="margin-right:4px">新建空项目</label>
    </div>
    <div id="areas-proj-path-row" style="margin-bottom:14px">
      <div style="font-size:12px;font-weight:500;margin-bottom:6px;color:var(--muted)">项目路径</div>
      <div style="display:flex;gap:6px">
        <input id="areas-proj-path" class="search" placeholder="/Users/bruce/Workspace/..." style="flex:1;height:32px;font-size:12px" />
        <button class="btn" style="font-size:12px;height:32px;padding:0 10px" onclick="document.getElementById('areas-proj-path').value='/Users/bruce/Workspace/新项目';document.getElementById('areas-proj-name').value='新项目'">📂 选择</button>
      </div>
    </div>
    <div style="margin-bottom:14px">
      <div style="font-size:12px;font-weight:500;margin-bottom:6px;color:var(--muted)">项目名称</div>
      <input id="areas-proj-name" class="search" placeholder="项目名称" style="width:100%;height:32px;font-size:12px" />
    </div>
    <div style="margin-bottom:20px">
      <div style="font-size:12px;font-weight:500;margin-bottom:6px;color:var(--muted)">项目类型标签</div>
      <select id="areas-proj-tag" style="background:var(--bg);border:1px solid var(--line);border-radius:var(--radius);color:var(--text);font-size:12px;padding:4px 8px;height:32px">
        <option value="执行">执行类</option>
        <option value="知识">知识类</option>
      </select>
    </div>
    <div style="display:flex;justify-content:flex-end;gap:8px">
      <button class="btn" onclick="document.getElementById('areas-add-project-modal').style.display='none'">取消</button>
      <button class="btn primary" id="areas-proj-confirm">添加</button>
    </div>
  </div>
</div>
```

- [ ] **Step 2: 绑定 radio 切换 + "添加项目"按钮 + 确认逻辑**

先在 HTML 中给侧边栏底部"+ 添加项目"按钮（`style` 含 `dashed`）添加 `id="areas-btn-add-project"`。

然后在 `initAreaProjects()` 内工具栏绑定代码之后添加：

```javascript
// ── 添加项目弹窗 ──
var addProjBtn = $('areas-btn-add-project');
if (addProjBtn) {
  addProjBtn.addEventListener('click', function() {
    $('areas-add-project-modal').style.display = 'flex';
    $('areas-proj-path').value = '';
    $('areas-proj-name').value = '';
    $('areas-proj-path-row').style.display = '';
    var localRadio = document.querySelector('input[name="areas-proj-type"][value="local"]');
    if (localRadio) localRadio.checked = true;
  });
}
$('areas-add-project-modal').addEventListener('click', function() { this.style.display = 'none'; });

// Radio 切换路径字段可见性
document.querySelectorAll('input[name="areas-proj-type"]').forEach(function(radio) {
  radio.addEventListener('change', function() {
    var pathRow = $('areas-proj-path-row');
    if (pathRow) pathRow.style.display = this.value === 'local' ? '' : 'none';
  });
});

var projConfirm = $('areas-proj-confirm');
if (projConfirm) {
  projConfirm.addEventListener('click', function() {
    var name = $('areas-proj-name').value.trim();
    if (!name) { showAreaToast('请输入项目名称'); return; }
    var projType = document.querySelector('input[name="areas-proj-type"]:checked').value;
    var path = $('areas-proj-path').value.trim();
    if (projType === 'local' && !path) { showAreaToast('请选择项目路径'); return; }
    var tag = $('areas-proj-tag').value;
    mockCounter++;
    var projId = 'mock-proj-' + mockCounter;
    var sidebar = document.querySelector('#areas-sidebar .side-scroll');
    var addBtn = sidebar.querySelector('div:last-child');
    var projEl = document.createElement('div');
    projEl.className = 'side-item area-project';
    projEl.dataset.areaId = projId;
    projEl.dataset.projType = projType;
    if (path) projEl.dataset.projPath = path;
    projEl.style.cursor = 'pointer';
    var pSpan = document.createElement('span');
    var pArrow = document.createElement('span');
    pArrow.className = 'area-arrow';
    pArrow.textContent = '▸';
    pSpan.appendChild(pArrow);
    pSpan.appendChild(document.createTextNode(' 📂 '));
    var pName = document.createElement('span');
    pName.className = 'area-name';
    pName.textContent = name;
    pSpan.appendChild(pName);
    projEl.appendChild(pSpan);
    var pPill = document.createElement('span');
    pPill.className = 'pill';
    pPill.style.cssText = 'font-size:9px;padding:1px 5px;margin-left:auto';
    pPill.textContent = tag;
    projEl.appendChild(pPill);
    var childrenEl = document.createElement('div');
    childrenEl.className = 'area-children collapsed';
    childrenEl.dataset.areaParent = projId;
    sidebar.insertBefore(projEl, addBtn);
    sidebar.insertBefore(childrenEl, addBtn);
    projEl.addEventListener('click', function(e) { if (e.target.closest('.area-file')) return; e.stopPropagation(); toggleFolder(this); });
    $('areas-add-project-modal').style.display = 'none';
    showAreaToast('已添加项目: ' + name + (projType === 'local' ? ' → ' + path : ' (空项目)'));
  });
}
```

- [ ] **Step 3: 验证**

1. 点击"+ 添加项目" → 弹窗出现，默认选中"指向本地目录"，路径行可见 ✓
2. 切换到"新建空项目" → 路径行隐藏 ✓
3. 切回"指向本地目录" → 路径行恢复 ✓
4. 输入名称 → 选择类型 → 点击"添加" → 文件树新增项目 + toast 包含类型信息 ✓
5. 点击空白处或"取消" → 弹窗关闭 ✓
6. **右键新增项目** → 菜单正常弹出（事件委托验证） ✓

- [ ] **Step 4: 提交**

```bash
git add docs/fp-ui/00-layout-prototype.html
git commit -m "feat(fp-ui): AreaProjects 添加项目弹窗——radio 切换 + 类型/路径 mock"
```

---

### Task 5: KB 卡片筛选 + Anki 同步反馈

**Files:**
- Modify: `docs/fp-ui/00-layout-prototype.html` — KB 视图 HTML + `initAreaProjects()` JS

- [ ] **Step 1: 给筛选按钮添加下拉菜单**

在 `initAreaProjects()` 内添加：

```javascript
// ── KB 筛选 ──
var kbFilterBtn = document.querySelector('#areas-kb .btn:not(.primary)');
if (kbFilterBtn) {
  kbFilterBtn.addEventListener('click', function(e) {
    e.stopPropagation();
    showContextMenu(e, [
      { icon: '🟡', label: 'know', action: function() { filterKBCards('know'); } },
      { icon: '🟢', label: 'understand', action: function() { filterKBCards('understand'); } },
      { icon: '🔵', label: 'master', action: function() { filterKBCards('master'); } },
      '---',
      { icon: '✅', label: '已同步', action: function() { filterKBCards('synced'); } },
      { icon: '⏳', label: '待同步', action: function() { filterKBCards('pending'); } },
      '---',
      { icon: '✕', label: '清除筛选', action: function() { filterKBCards(''); } }
    ]);
  });
}

function filterKBCards(filter) {
  document.querySelectorAll('.area-kb-card').forEach(function(card) {
    if (!filter) { card.style.display = ''; return; }
    var text = card.textContent.toLowerCase();
    if (filter === 'synced') { card.style.display = text.indexOf('已同步') !== -1 ? '' : 'none'; }
    else if (filter === 'pending') { card.style.display = text.indexOf('待同步') !== -1 ? '' : 'none'; }
    else { card.style.display = text.indexOf(filter) !== -1 ? '' : 'none'; }
  });
  showAreaToast(filter ? '已筛选: ' + filter : '已清除筛选');
}
```

- [ ] **Step 2: Anki 同步按钮反馈**

```javascript
// ── Anki 同步反馈 ──
var ankiBtn = document.querySelector('#areas-kb .btn.primary');
if (ankiBtn) {
  ankiBtn.addEventListener('click', function() {
    var pending = document.querySelectorAll('.area-kb-card');
    var count = 0;
    pending.forEach(function(card) {
      var syncSpan = card.querySelector('span[style*="color:var(--amber)"]');
      if (syncSpan && syncSpan.textContent.indexOf('待同步') !== -1) {
        syncSpan.style.color = 'var(--green)';
        syncSpan.textContent = '✅ 已同步';
        count++;
      }
    });
    showAreaToast(count > 0 ? '已同步 ' + count + ' 张卡片到 Anki' : '没有待同步的卡片');
  });
}
```

- [ ] **Step 3: 验证**

1. KB 卡片视图 → 点击"筛选" → 下拉菜单（know/understand/master/已同步/待同步/清除） ✓
2. 选择"know" → 仅显示 know 等级卡片 ✓
3. 选择"清除筛选" → 恢复全部 ✓
4. 点击"同步 Anki" → 待同步卡片状态变为"✅ 已同步" + toast ✓

- [ ] **Step 4: 提交**

```bash
git add docs/fp-ui/00-layout-prototype.html
git commit -m "feat(fp-ui): AreaProjects KB 卡片筛选 + Anki 同步反馈"
```

---

### Task 6: 搜索过滤改进 + 面包屑点击

**Files:**
- Modify: `docs/fp-ui/00-layout-prototype.html` — `initAreaProjects()` JS

- [ ] **Step 1: 改进搜索——保存/恢复展开状态**

将现有搜索代码（`// ── (g) 搜索过滤 ──` 块）替换为带状态保存的版本。在搜索输入框 `input` 事件处理前保存展开状态，清空搜索时恢复：

```javascript
// ── (g) 搜索过滤（改进版） ──
var searchInput = $('areas-search');
var savedFolderStates = null;

if (searchInput) {
  searchInput.addEventListener('input', function() {
    var q = this.value.trim().toLowerCase();

    if (q && !savedFolderStates) {
      savedFolderStates = {};
      document.querySelectorAll('#areas-sidebar .area-children').forEach(function(c) {
        savedFolderStates[c.dataset.areaParent] = c.classList.contains('collapsed');
      });
    }

    if (!q && savedFolderStates) {
      document.querySelectorAll('#areas-sidebar .area-children').forEach(function(c) {
        var wasCollapsed = savedFolderStates[c.dataset.areaParent];
        c.classList.toggle('collapsed', wasCollapsed !== undefined ? wasCollapsed : true);
        var parentEl = document.querySelector('[data-area-id="' + c.dataset.areaParent + '"]');
        if (parentEl) {
          var arrow = parentEl.querySelector('.area-arrow');
          if (arrow) arrow.textContent = c.classList.contains('collapsed') ? '▸' : '▾';
        }
      });
      savedFolderStates = null;
    }

    document.querySelectorAll('#areas-sidebar .area-file').forEach(function(el) {
      var text = el.textContent.toLowerCase();
      el.style.display = (!q || text.indexOf(q) !== -1) ? '' : 'none';
    });
    document.querySelectorAll('#areas-sidebar .area-project').forEach(function(el) {
      var text = el.textContent.toLowerCase();
      var areaId = el.dataset.areaId;
      var children = document.querySelector('.area-children[data-area-parent="' + areaId + '"]');
      if (!q) { el.style.display = ''; return; }
      var hasVisibleChild = false;
      if (children) {
        children.querySelectorAll('.area-file').forEach(function(f) { if (f.style.display !== 'none') hasVisibleChild = true; });
      }
      if (text.indexOf(q) !== -1 || hasVisibleChild) {
        el.style.display = '';
        if (children && hasVisibleChild) children.classList.remove('collapsed');
        var arrow = el.querySelector('.area-arrow');
        if (arrow && children && !children.classList.contains('collapsed')) arrow.textContent = '▾';
      } else {
        el.style.display = 'none';
      }
    });
    document.querySelectorAll('#areas-sidebar .area-folder').forEach(function(el) {
      var areaId = el.dataset.areaId;
      var children = document.querySelector('.area-children[data-area-parent="' + areaId + '"]');
      if (!q) { el.style.display = ''; return; }
      var hasVisibleChild = false;
      if (children) {
        children.querySelectorAll('.area-file').forEach(function(f) { if (f.style.display !== 'none') hasVisibleChild = true; });
      }
      if (hasVisibleChild || el.textContent.toLowerCase().indexOf(q) !== -1) {
        el.style.display = '';
        if (children && hasVisibleChild) children.classList.remove('collapsed');
        var arrow = el.querySelector('.area-arrow');
        if (arrow && children && !children.classList.contains('collapsed')) arrow.textContent = '▾';
      } else {
        el.style.display = 'none';
      }
    });
  });

  searchInput.addEventListener('keydown', function(e) {
    if (e.key === 'Escape') { this.value = ''; this.dispatchEvent(new Event('input')); this.blur(); }
  });
}
```

- [ ] **Step 2: 面包屑点击跳转**

在 `initAreaProjects()` 内添加：

```javascript
// ── 面包屑点击 ──
var breadcrumb = $('areas-breadcrumb');
if (breadcrumb) {
  breadcrumb.style.cursor = 'pointer';
  breadcrumb.addEventListener('click', function() {
    var parts = this.textContent.replace(/^📂\s*/, '').split(' / ');
    if (parts.length < 2) return;
    var projName = parts[0].trim();
    document.querySelectorAll('#areas-sidebar .area-project').forEach(function(p) {
      var nameSpan = p.querySelector('.area-name');
      var name = nameSpan ? nameSpan.textContent.trim() : p.textContent.replace(/[▾▸📂]\s*/g, '').replace(/执行|知识/g, '').trim();
      if (name === projName) {
        var areaId = p.dataset.areaId;
        var children = document.querySelector('.area-children[data-area-parent="' + areaId + '"]');
        if (children) children.classList.remove('collapsed');
        var arrow = p.querySelector('.area-arrow');
        if (arrow) arrow.textContent = '▾';
        p.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
      }
    });
  });
}
```

- [ ] **Step 3: 验证**

1. 搜索框输入"CAP" → 文件树过滤显示匹配项 ✓
2. 清空搜索框 → 文件树恢复原来的展开/折叠状态 ✓
3. Esc → 搜索框清空并恢复 ✓
4. 点击面包屑 → 侧边栏对应项目展开并滚动到可见 ✓

- [ ] **Step 4: 提交**

```bash
git add docs/fp-ui/00-layout-prototype.html
git commit -m "feat(fp-ui): AreaProjects 搜索过滤保存/恢复展开状态 + Esc 清空 + 面包屑点击跳转"
```

---

### Task 7: 状态更新 + 文档联动

**Files:**
- Modify: `CLAUDE.md` — UI 设计进度表 AreaProjects 行
- Modify: `docs/fp-ui/05-area-projects.md` — 顶部状态行
- Modify: `docs/FP-UI.md` — UI 总览页 AreaProjects 行
- Check: `docs/PRD.md` — 确认无需变更
- Check: `docs/DesignGuide.md` — 确认无需变更

- [ ] **Step 1: 更新 CLAUDE.md 进度表**

找到 `| 05-area-projects |` 行，改为：
```
| 05-area-projects | 5/5 | 可开发 | — |
```

- [ ] **Step 2: 更新 05-area-projects.md 顶部状态**

将第 3 行 `> **状态**：设计中` 改为 `> **状态**：可开发（UI 母版原型可开发，非 Swift 已实现）`。
将第 4 行 `> **更新**：2026-05-27` 改为 `> **更新**：2026-05-28`。

- [ ] **Step 3: 更新 docs/FP-UI.md AreaProjects 行**

找到 FP-UI.md 中 AreaProjects 对应行（约第 132 行附近），将规格状态从"设计中"改为"可开发（UI 母版）"，与 CLAUDE.md 和 05-area-projects.md 保持一致。注意：FP-UI.md 的列名可能是"规格状态"而非"完整度"，以实际列名为准。

- [ ] **Step 4: 检查 PRD + DesignGuide**

确认 PRD 中 AreaProjects 相关章节无需因交互补齐而修改（交互属 UI 层，PRD 定义功能边界）。DesignGuide 无新增色值或动画参数。

- [ ] **Step 5: 提交**

```bash
git add CLAUDE.md docs/fp-ui/05-area-projects.md docs/FP-UI.md
git commit -m "docs(fp-ui): AreaProjects 状态更新为 5/5 可开发

- CLAUDE.md 进度表更新
- 05-area-projects.md 顶部状态从'设计中'改为'可开发（UI 母版原型可开发，非 Swift 已实现）'
- FP-UI.md 总览页同步更新
- PRD/DesignGuide 无需变更"
```

---

### Task 8: 最终串联验收

- [ ] **Step 1: 全流程串联测试**

浏览器打开原型，按以下路径验证：

1. **角标修正**：_reports 文件夹无数字角标 ✓
2. **右键菜单**：分别右键文件/文件夹/项目/_materials/_kb → 对应菜单项显示正确 ✓
3. **新建文件**：右键项目 → "新建文件" → 文件出现 + 编辑器打开 ✓
4. **新建文件夹**：工具栏 📁 → 文件夹出现 ✓
5. **动态节点菜单**：右键新建的文件/文件夹 → 菜单正常弹出 ✓
6. **删除**：右键文件 → "删除" → 文件消失 + toast"已删除" ✓
7. **重命名**：右键文件 → "重命名" → 内联编辑 → Enter 确认 ✓
8. **收藏筛选**：右键项目 → "收藏" → 工具栏 ⭐ → 仅显示已收藏 ✓
9. **Tab 管理**：打开多个文件 → Tab 新增 → 关闭 Tab → 空状态 ✓
10. **添加项目**：点击"+ 添加项目" → 切换 radio → 路径行显隐 → 确认 → 项目出现 ✓
11. **KB 筛选**：KB 视图 → "筛选" → 选择等级 → 过滤 → 清除 ✓
12. **Anki 同步**：点击"同步 Anki" → 待同步变已同步 ✓
13. **搜索**：输入关键词 → 过滤 → Esc 恢复展开状态 ✓
14. **面包屑**：点击面包屑 → 项目展开并滚动到可见 ✓
15. **终端/Agent 占位**：终端底部有提示，Agent 发送显示 toast ✓

- [ ] **Step 2: 输出 UI 设计进度表**

输出当前 UI 设计进度表（各页面完整度和状态），确认 05-area-projects 已更新为 5/5 可开发。

- [ ] **Step 3: 浏览器打开母版原型**

用浏览器打开 `docs/fp-ui/00-layout-prototype.html`，停留在页面等待用户自行查看验收。不用截图替代。

- [ ] **Step 4: 确认工作区干净并推送**

```bash
git status --short
git push
```

---

## Self-Review

1. **Spec coverage**: 右键菜单 4 种类型（事件委托） ✓；CRUD mock（新建文件/文件夹、删除、重命名，.area-name 精确定位） ✓；工具栏（📁📄⭐⤡）✓；Tab 管理（关闭+动态新增+空状态，稳定 ID） ✓；KB 筛选 ✓；Anki 同步反馈 ✓；添加项目弹窗（radio 切换路径可见性） ✓；搜索过滤保存/恢复 + Esc ✓；面包屑点击 ✓；_reports 角标修正 ✓；终端/Agent 占位标注 ✓；状态更新（含"非 Swift 已实现"说明） ✓；验收输出进度表+浏览器打开 ✓
2. **降级说明**：拖拽（D&D）、多选（Cmd+click）、自动保存（setInterval+⌘S）、Tab 拖拽排序、脏标记（●）为原型阶段降级项，规格已定义但不影响"可开发"判定——这些是开发实现细节，不是设计缺失。搜索为"过滤"模式，非规格的"结果区"，后续 Swift 开发时补完
3. **Placeholder scan**: 无 TBD/TODO，所有步骤含完整代码
4. **Type consistency**: `showAreaToast` / `showContextMenu` / `hideContextMenu` / `createMockFile` / `createMockFolder` / `deleteFileNode` / `deleteFolderNode` / `removeProject` / `startRename` / `filterKBCards` / `closeTab` / `.area-name` / `.area-hidden` 命名一致；`areaFiles` 数据对象在所有函数中共享
5. **Codex review 修正（第一轮）**: Task 2+3 合并（消除 broken 中间提交） ✓；事件委托（动态节点自动获得菜单） ✓；稳定 ID 替代 style*= 选择器 ✓；.area-name 替代 span:last-child（避免误选箭头） ✓；删除 toast 去掉假"撤销" ✓；弹窗 radio 联动路径字段 ✓；搜索任务改名"过滤" ✓；验收补进度表+浏览器 ✓；_reports"三处"改"两处" ✓；验证描述对齐实现 ✓
6. **Codex review 修正（第二轮）**: FP-UI.md 同步更新 ✓；startRename Esc 取消加 cancelled 标志防 blur 覆盖 ✓；deleteFileNode 同步关闭已打开 Tab ✓；"指向本地目录"空路径校验 ✓；添加项目按钮改用稳定 id ✓；Architecture 描述修正 closeTab 全局例外 ✓
7. **Codex review 修正（第三轮）**: deleteFileNode 对 closeTab 加 typeof 防御（Task 2 阶段 closeTab 未定义时 fallback remove） ✓；FP-UI.md 步骤措辞改为"规格状态"避免列名不匹配 ✓；createMockFile/createMockFolder/添加项目改用 createElement + textContent 构造（消除 innerHTML 注入风险） ✓
8. **Codex review 修正（第四轮）**: openFile 动态 Tab 也改用 createElement + textContent 构造（消除最后一个 innerHTML 拼接用户输入点） ✓
