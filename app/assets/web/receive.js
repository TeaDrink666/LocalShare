'use strict';

const BASE_URL = '/api/localsend/v2';
const FINGERPRINT_KEY = 'localshare.web.fingerprint.v1';

const COPY = {
  en: {
    pageTitle: 'Send to LocalShare',
    eyebrow: 'Browser upload',
    title: 'Send files to this device',
    initialStatus: 'Choose files or a folder to begin.',
    dropTitle: 'Drop files here',
    dropHelp: 'They are sent directly over your local network—nothing is uploaded to the cloud.',
    chooseFiles: 'Choose files',
    chooseFolder: 'Choose folder',
    selectedFiles: 'Selected files',
    newTransfer: 'New transfer',
    retry: 'Try again',
    send: 'Send files',
    footer: 'Keep this page open until the transfer finishes.',
    files: 'files',
    file: 'file',
    ready: 'Ready to send',
    queued: 'Queued',
    awaiting: 'Awaiting approval',
    uploading: 'Sending',
    sent: 'Sent',
    skipped: 'Not accepted',
    failed: 'Failed',
    preparing: 'Sending request…',
    waitingApproval: 'Waiting for approval on the receiving device…',
    approvalHint: 'Confirm this transfer on the receiving device.',
    sendingNow: 'Sending {current} of {total}: {name}',
    complete: 'Transfer complete',
    completeDetail: '{sent} sent{skipped}',
    skippedDetail: ', {count} not accepted',
    noneAccepted: 'The recipient did not accept any files.',
    transferComplete: 'All accepted files were sent successfully.',
    enterPin: 'Enter the receiving device PIN:',
    invalidPin: 'That PIN was not accepted. Try again:',
    pinCanceled: 'PIN entry was canceled. You can try again when ready.',
    declined: 'The recipient declined this transfer.',
    busy: 'The receiving device is busy with another transfer.',
    tooMany: 'Too many PIN attempts. Wait a moment, then try again.',
    forbidden: 'The receiving device no longer accepts this session.',
    conflict: 'The receiving session is no longer available.',
    networkError: 'Could not reach the receiving device. Check the local network and try again.',
    prepareError: 'Could not request this transfer ({status}).',
    uploadError: 'Could not send “{name}” ({status}).',
    invalidResponse: 'The receiving device returned an invalid response.',
    noFiles: 'Choose at least one file first.',
    readingFolder: 'Reading dropped folder…',
    removeFile: 'Remove {name}',
    folderUnsupported: 'This browser could not read the dropped folder. Use “Choose folder” instead.',
    browserAlias: 'Web browser',
    unknownStatus: 'network error'
  },
  zh: {
    pageTitle: '发送到 LocalShare',
    eyebrow: '浏览器上传',
    title: '发送文件到此设备',
    initialStatus: '选择文件或文件夹即可开始。',
    dropTitle: '拖放文件到这里',
    dropHelp: '文件仅通过局域网直接传输，不会上传到云端。',
    chooseFiles: '选择文件',
    chooseFolder: '选择文件夹',
    selectedFiles: '已选文件',
    newTransfer: '新建传输',
    retry: '重试',
    send: '开始发送',
    footer: '传输完成前请保持此页面打开。',
    files: '个文件',
    file: '个文件',
    ready: '准备发送',
    queued: '等待发送',
    awaiting: '等待确认',
    uploading: '发送中',
    sent: '已发送',
    skipped: '未接收',
    failed: '发送失败',
    preparing: '正在发起请求…',
    waitingApproval: '正在等待接收设备确认…',
    approvalHint: '请在接收设备上确认本次传输。',
    sendingNow: '正在发送第 {current}/{total} 个：{name}',
    complete: '传输完成',
    completeDetail: '已发送 {sent} 个文件{skipped}',
    skippedDetail: '，{count} 个未接收',
    noneAccepted: '接收方没有接受任何文件。',
    transferComplete: '接收方接受的文件已全部发送完成。',
    enterPin: '请输入接收设备的 PIN：',
    invalidPin: 'PIN 不正确，请重试：',
    pinCanceled: '已取消输入 PIN，可随时重试。',
    declined: '接收方拒绝了本次传输。',
    busy: '接收设备正在处理另一项传输。',
    tooMany: 'PIN 尝试次数过多，请稍后再试。',
    forbidden: '接收设备已不再接受此传输会话。',
    conflict: '接收会话已不可用。',
    networkError: '无法连接接收设备，请检查局域网后重试。',
    prepareError: '无法发起传输请求（{status}）。',
    uploadError: '无法发送“{name}”（{status}）。',
    invalidResponse: '接收设备返回了无效响应。',
    noFiles: '请先选择至少一个文件。',
    readingFolder: '正在读取拖入的文件夹…',
    removeFile: '移除 {name}',
    folderUnsupported: '当前浏览器无法读取拖入的文件夹，请改用“选择文件夹”。',
    browserAlias: '网页浏览器',
    unknownStatus: '网络错误'
  }
};

const language = /^zh(?:-|$)/i.test(navigator.language || '') ? 'zh' : 'en';
const t = COPY[language];

const elements = {
  dropZone: document.getElementById('drop-zone'),
  fileInput: document.getElementById('file-input'),
  folderInput: document.getElementById('folder-input'),
  pickFiles: document.getElementById('pick-files'),
  pickFolder: document.getElementById('pick-folder'),
  fileList: document.getElementById('file-list'),
  selectionSummary: document.getElementById('selection-summary'),
  heroStatus: document.getElementById('hero-status'),
  progressTitle: document.getElementById('progress-title'),
  progressDetail: document.getElementById('progress-detail'),
  totalProgress: document.querySelector('.total-progress'),
  totalProgressBar: document.getElementById('total-progress-bar'),
  sendButton: document.getElementById('send-button'),
  sendButtonLabel: document.getElementById('send-button-label'),
  retryButton: document.getElementById('retry-transfer'),
  newTransferButton: document.getElementById('new-transfer'),
  notice: document.getElementById('notice')
};

let entries = [];
let rowElements = new Map();
let locked = false;
let selectionFrozen = false;
let session = null;
let retryMode = 'prepare';
let rememberedPin = null;

function applyStaticCopy() {
  document.documentElement.lang = language === 'zh' ? 'zh-CN' : 'en';
  document.title = t.pageTitle;
  document.querySelectorAll('[data-i18n]').forEach((node) => {
    const value = t[node.dataset.i18n];
    if (value) node.textContent = value;
  });
  elements.heroStatus.textContent = t.initialStatus;
  elements.progressTitle.textContent = t.ready;
}

function interpolate(template, values) {
  return template.replace(/\{(\w+)\}/g, (_, key) => String(values[key] ?? ''));
}

function createId() {
  if (globalThis.crypto && typeof globalThis.crypto.randomUUID === 'function') {
    return globalThis.crypto.randomUUID();
  }

  if (globalThis.crypto && typeof globalThis.crypto.getRandomValues === 'function') {
    const bytes = new Uint8Array(16);
    globalThis.crypto.getRandomValues(bytes);
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    const hex = Array.from(bytes, (value) => value.toString(16).padStart(2, '0')).join('');
    return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
  }

  return `web-${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}-${Math.random().toString(36).slice(2)}`;
}

function getFingerprint() {
  let fingerprint = null;
  try {
    fingerprint = localStorage.getItem(FINGERPRINT_KEY);
  } catch (_) {
    // Storage can be unavailable in private or locked-down browsing contexts.
  }

  if (!fingerprint) {
    fingerprint = `web-${createId()}`;
    try {
      localStorage.setItem(FINGERPRINT_KEY, fingerprint);
    } catch (_) {
      // The page still works; only the identity will not survive a reload.
    }
  }

  return fingerprint;
}

function getBrowserModel() {
  const ua = navigator.userAgent || '';
  if (/Edg\//.test(ua)) return 'Microsoft Edge';
  if (/OPR\//.test(ua)) return 'Opera';
  if (/Firefox\//.test(ua)) return 'Firefox';
  if (/Chrome\//.test(ua)) return 'Google Chrome';
  if (/Safari\//.test(ua)) return 'Safari';
  return 'Web';
}

function getDeviceInfo() {
  const defaultPort = location.protocol === 'https:' ? 443 : 80;
  return {
    alias: t.browserAlias,
    version: '2.1',
    deviceModel: getBrowserModel(),
    deviceType: 'web',
    fingerprint: getFingerprint(),
    port: Number(location.port) || defaultPort,
    protocol: location.protocol === 'https:' ? 'https' : 'http',
    download: false
  };
}

function normalizePath(path, fallback) {
  const safe = String(path || fallback)
    .replace(/\\/g, '/')
    .replace(/^\/+/, '')
    .split('/')
    .filter((part) => part && part !== '.' && part !== '..')
    .join('/');
  return safe || fallback;
}

function addFiles(filesWithPaths) {
  if (selectionIsLocked()) return;

  const known = new Set(entries.map((entry) => `${entry.path}\u0000${entry.file.size}\u0000${entry.file.lastModified}`));
  filesWithPaths.forEach(({ file, path }) => {
    if (!(file instanceof File)) return;
    const normalizedPath = normalizePath(path || file.webkitRelativePath || file.name, file.name);
    const key = `${normalizedPath}\u0000${file.size}\u0000${file.lastModified}`;
    if (known.has(key)) return;
    known.add(key);
    entries.push({
      id: createId(),
      file,
      path: normalizedPath,
      status: 'queued',
      loaded: 0,
      token: null,
      error: null
    });
  });

  resetTransferUi();
  renderFileList();
  updateSummary();
}

function filesFromInput(fileList) {
  return Array.from(fileList || [], (file) => ({
    file,
    path: file.webkitRelativePath || file.name
  }));
}

function readFileEntry(entry) {
  return new Promise((resolve, reject) => entry.file(resolve, reject));
}

function readDirectoryEntries(reader) {
  return new Promise((resolve, reject) => {
    const all = [];
    const readBatch = () => {
      reader.readEntries((batch) => {
        if (!batch.length) {
          resolve(all);
          return;
        }
        all.push(...batch);
        readBatch();
      }, reject);
    };
    readBatch();
  });
}

async function walkEntry(entry) {
  if (entry.isFile) {
    const file = await readFileEntry(entry);
    return [{ file, path: normalizePath(entry.fullPath, file.name) }];
  }

  if (!entry.isDirectory) return [];
  const children = await readDirectoryEntries(entry.createReader());
  const nested = await Promise.all(children.map(walkEntry));
  return nested.flat();
}

async function filesFromDrop(dataTransfer) {
  const items = Array.from(dataTransfer.items || []);
  const entryItems = items
    .map((item) => (typeof item.webkitGetAsEntry === 'function' ? item.webkitGetAsEntry() : null))
    .filter(Boolean);

  if (entryItems.length) {
    const nested = await Promise.all(entryItems.map(walkEntry));
    const files = nested.flat();
    if (files.length) return files;
  }

  return filesFromInput(dataTransfer.files);
}

function formatBytes(bytes) {
  if (!Number.isFinite(bytes) || bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  const index = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), units.length - 1);
  const value = bytes / Math.pow(1024, index);
  return `${value.toFixed(index === 0 || value >= 100 ? 0 : 1)} ${units[index]}`;
}

function fileStateText(entry) {
  switch (entry.status) {
    case 'awaiting': return t.awaiting;
    case 'uploading': return `${t.uploading} ${Math.round(fileFraction(entry) * 100)}%`;
    case 'sent': return t.sent;
    case 'skipped': return t.skipped;
    case 'failed': return t.failed;
    default: return t.queued;
  }
}

function fileFraction(entry) {
  if (entry.status === 'sent') return 1;
  if (entry.file.size === 0) return entry.status === 'uploading' ? 0 : 0;
  return Math.min(1, Math.max(0, entry.loaded / entry.file.size));
}

function fileIcon() {
  const span = document.createElement('span');
  span.className = 'file-icon';
  span.setAttribute('aria-hidden', 'true');
  span.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8Z"></path><path d="M14 2v6h6"></path><path d="M8 13h8"></path><path d="M8 17h5"></path></svg>';
  return span;
}

function renderFileList() {
  rowElements = new Map();
  elements.fileList.replaceChildren();

  entries.forEach((entry) => {
    const row = document.createElement('div');
    row.className = 'file-item';
    row.dataset.fileId = entry.id;

    const main = document.createElement('div');
    main.className = 'file-main';

    const line = document.createElement('div');
    line.className = 'file-line';
    const name = document.createElement('span');
    name.className = 'file-name';
    name.textContent = entry.file.name;
    name.title = entry.path;
    const size = document.createElement('span');
    size.className = 'file-size';
    size.textContent = formatBytes(entry.file.size);
    line.append(name, size);

    const path = document.createElement('div');
    path.className = 'file-path';
    path.textContent = entry.path;
    path.title = entry.path;

    const progress = document.createElement('div');
    progress.className = 'file-progress';
    const progressBar = document.createElement('div');
    progressBar.className = 'file-progress-bar';
    progress.append(progressBar);
    main.append(line, path, progress);

    const side = document.createElement('div');
    side.className = 'file-side';
    const state = document.createElement('span');
    state.className = 'file-state';

    const remove = document.createElement('button');
    remove.className = 'remove-button';
    remove.type = 'button';
    remove.setAttribute('aria-label', interpolate(t.removeFile, { name: entry.file.name }));
    remove.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M18 6 6 18"></path><path d="m6 6 12 12"></path></svg>';
    remove.addEventListener('click', () => removeEntry(entry.id));
    side.append(state, remove);

    row.append(fileIcon(), main, side);
    elements.fileList.append(row);
    rowElements.set(entry.id, { state, progressBar, remove });
    updateFileRow(entry);
  });
}

function updateFileRow(entry) {
  const row = rowElements.get(entry.id);
  if (!row) return;
  const fraction = entry.status === 'sent' ? 1 : fileFraction(entry);
  row.progressBar.style.width = `${fraction * 100}%`;
  row.state.textContent = fileStateText(entry);
  row.state.classList.toggle('is-success', entry.status === 'sent');
  row.state.classList.toggle('is-error', entry.status === 'failed');
  row.remove.hidden = selectionIsLocked();
}

function removeEntry(id) {
  if (selectionIsLocked()) return;
  entries = entries.filter((entry) => entry.id !== id);
  resetTransferUi();
  renderFileList();
  updateSummary();
}

function selectionText(count, bytes) {
  const noun = count === 1 ? t.file : t.files;
  return language === 'zh'
    ? `${count} ${noun} · ${formatBytes(bytes)}`
    : `${count} ${noun} · ${formatBytes(bytes)}`;
}

function updateSummary() {
  const bytes = entries.reduce((sum, entry) => sum + entry.file.size, 0);
  const selectionLocked = selectionIsLocked();
  elements.selectionSummary.textContent = selectionText(entries.length, bytes);
  elements.sendButton.disabled = locked || entries.length === 0;
  elements.dropZone.classList.toggle('is-disabled', selectionLocked);
  elements.dropZone.setAttribute('aria-disabled', String(selectionLocked));
  elements.fileInput.disabled = selectionLocked;
  elements.folderInput.disabled = selectionLocked;
  entries.forEach(updateFileRow);
  updateTotalProgress();
}

function selectionIsLocked() {
  return locked || selectionFrozen;
}

function transferEntries() {
  const accepted = entries.filter((entry) => entry.token || ['uploading', 'sent', 'failed'].includes(entry.status));
  return accepted.length ? accepted : entries.filter((entry) => entry.status !== 'skipped');
}

function updateTotalProgress() {
  const active = transferEntries();
  const totalBytes = active.reduce((sum, entry) => sum + entry.file.size, 0);
  const uploadedBytes = active.reduce((sum, entry) => {
    if (entry.status === 'sent') return sum + entry.file.size;
    return sum + Math.min(entry.loaded, entry.file.size);
  }, 0);
  const completed = active.filter((entry) => entry.status === 'sent').length;
  const fraction = totalBytes > 0
    ? uploadedBytes / totalBytes
    : (active.length ? completed / active.length : 0);
  const percent = Math.min(100, Math.max(0, Math.round(fraction * 100)));

  elements.totalProgressBar.style.width = `${percent}%`;
  elements.totalProgress.setAttribute('aria-valuenow', String(percent));
  elements.progressDetail.textContent = totalBytes > 0
    ? `${percent}% · ${formatBytes(uploadedBytes)} / ${formatBytes(totalBytes)}`
    : `${percent}%`;
}

function setLocked(value) {
  locked = value;
  updateSummary();
}

function showNotice(message, success = false) {
  elements.notice.textContent = message;
  elements.notice.classList.toggle('is-success', success);
  elements.notice.classList.toggle('is-visible', Boolean(message));
}

function setHeroStatus(message) {
  elements.heroStatus.textContent = message;
}

function resetTransferUi() {
  session = null;
  retryMode = 'prepare';
  elements.retryButton.hidden = true;
  elements.newTransferButton.hidden = true;
  elements.sendButton.hidden = false;
  elements.sendButtonLabel.textContent = t.send;
  elements.progressTitle.textContent = t.ready;
  setHeroStatus(entries.length ? t.initialStatus : t.initialStatus);
  showNotice('');
}

function pendingEntries() {
  return entries.filter((entry) => !['sent', 'skipped'].includes(entry.status));
}

function makePreparePayload(requestEntries) {
  const files = {};
  requestEntries.forEach((entry) => {
    files[entry.id] = {
      id: entry.id,
      fileName: entry.path,
      size: entry.file.size,
      fileType: entry.file.type || 'application/octet-stream'
    };
  });
  return { info: getDeviceInfo(), files };
}

function request(method, url, body, contentType) {
  return new Promise((resolve) => {
    const xhr = new XMLHttpRequest();
    xhr.open(method, url, true);
    if (contentType) xhr.setRequestHeader('Content-Type', contentType);
    xhr.onload = () => resolve(xhr);
    xhr.onerror = () => resolve(xhr);
    xhr.onabort = () => resolve(xhr);
    xhr.send(body);
  });
}

async function requestApproval(requestEntries) {
  let invalidPin = false;

  while (true) {
    const pinQuery = rememberedPin ? `?pin=${encodeURIComponent(rememberedPin)}` : '';
    const pendingRequest = request(
      'POST',
      `${BASE_URL}/prepare-upload${pinQuery}`,
      JSON.stringify(makePreparePayload(requestEntries)),
      'application/json'
    );

    elements.progressTitle.textContent = t.awaiting;
    elements.sendButtonLabel.textContent = t.awaiting;
    setHeroStatus(t.waitingApproval);
    showNotice('');
    requestEntries.forEach((entry) => {
      entry.status = 'awaiting';
      entry.loaded = 0;
      updateFileRow(entry);
    });

    const response = await pendingRequest;
    if (response.status !== 401) return response;

    const pin = window.prompt(invalidPin ? t.invalidPin : t.enterPin);
    if (pin === null) {
      rememberedPin = null;
      throw new TransferError('pin-canceled', 401, t.pinCanceled);
    }

    rememberedPin = pin.trim();
    invalidPin = true;
  }
}

class TransferError extends Error {
  constructor(kind, status, message, entry = null) {
    super(message);
    this.name = 'TransferError';
    this.kind = kind;
    this.status = status;
    this.entry = entry;
  }
}

function parseApproval(response) {
  if (response.status === 204) return { sessionId: null, files: {} };
  if (response.status !== 200) throw prepareStatusError(response.status);

  try {
    const parsed = JSON.parse(response.responseText);
    if (!parsed || typeof parsed.sessionId !== 'string' || !parsed.files || typeof parsed.files !== 'object') {
      throw new Error('shape');
    }
    return parsed;
  } catch (_) {
    throw new TransferError('prepare', response.status, t.invalidResponse);
  }
}

function prepareStatusError(status) {
  if (status === 0) return new TransferError('prepare', status, t.networkError);
  if (status === 403) return new TransferError('prepare', status, t.declined);
  if (status === 409) return new TransferError('prepare', status, t.busy);
  if (status === 429) return new TransferError('prepare', status, t.tooMany);
  return new TransferError('prepare', status, interpolate(t.prepareError, { status }));
}

function uploadStatusError(entry, status) {
  if (status === 0) return new TransferError('upload', status, t.networkError, entry);
  if (status === 403) return new TransferError('session', status, t.forbidden, entry);
  if (status === 409) return new TransferError('session', status, t.conflict, entry);
  if (status === 429) return new TransferError('session', status, t.tooMany, entry);
  return new TransferError('upload', status, interpolate(t.uploadError, {
    name: entry.file.name,
    status: status || t.unknownStatus
  }), entry);
}

function uploadFile(entry) {
  return new Promise((resolve, reject) => {
    const query = new URLSearchParams({
      sessionId: session.sessionId,
      fileId: entry.id,
      token: entry.token
    });
    const xhr = new XMLHttpRequest();
    xhr.open('POST', `${BASE_URL}/upload?${query.toString()}`, true);
    xhr.setRequestHeader('Content-Type', entry.file.type || 'application/octet-stream');

    xhr.upload.onprogress = (event) => {
      entry.loaded = event.lengthComputable ? event.loaded : Math.min(entry.file.size, event.loaded || 0);
      entry.status = 'uploading';
      updateFileRow(entry);
      updateTotalProgress();
    };

    xhr.onload = () => {
      if (xhr.status >= 200 && xhr.status < 300) {
        entry.loaded = entry.file.size;
        entry.status = 'sent';
        entry.error = null;
        updateFileRow(entry);
        updateTotalProgress();
        resolve();
      } else {
        reject(uploadStatusError(entry, xhr.status));
      }
    };
    xhr.onerror = () => reject(uploadStatusError(entry, 0));
    xhr.onabort = () => reject(uploadStatusError(entry, 0));
    xhr.send(entry.file);
  });
}

async function uploadAcceptedFiles() {
  const queue = entries.filter((entry) => entry.token && entry.status !== 'sent');
  const total = queue.length;
  elements.progressTitle.textContent = t.uploading;
  showNotice('');

  for (let index = 0; index < queue.length; index += 1) {
    const entry = queue[index];
    entry.status = 'uploading';
    entry.error = null;
    updateFileRow(entry);
    setHeroStatus(interpolate(t.sendingNow, {
      current: index + 1,
      total,
      name: entry.file.name
    }));

    try {
      await uploadFile(entry);
    } catch (error) {
      entry.status = 'failed';
      entry.error = error.message;
      updateFileRow(entry);
      throw error;
    }
  }

  finishTransfer();
}

function finishTransfer() {
  const sent = entries.filter((entry) => entry.status === 'sent').length;
  const skipped = entries.filter((entry) => entry.status === 'skipped').length;
  const skippedText = skipped ? interpolate(t.skippedDetail, { count: skipped }) : '';
  elements.progressTitle.textContent = t.complete;
  elements.progressDetail.textContent = '100%';
  elements.totalProgressBar.style.width = '100%';
  elements.totalProgress.setAttribute('aria-valuenow', '100');
  elements.sendButton.hidden = true;
  elements.retryButton.hidden = true;
  elements.newTransferButton.hidden = false;
  setHeroStatus(interpolate(t.completeDetail, { sent, skipped: skippedText }));
  showNotice(sent ? t.transferComplete : t.noneAccepted, true);
  setLocked(true);
}

async function beginTransfer(onlyPending = false) {
  if (locked) return;
  const requestEntries = onlyPending ? pendingEntries() : entries;
  if (!requestEntries.length) {
    showNotice(t.noFiles);
    return;
  }

  selectionFrozen = true;
  setLocked(true);
  session = null;
  elements.retryButton.hidden = true;
  elements.newTransferButton.hidden = true;
  elements.sendButton.hidden = false;
  elements.sendButton.disabled = true;
  elements.sendButtonLabel.textContent = t.preparing;
  showNotice('');
  setHeroStatus(t.preparing);

  requestEntries.forEach((entry) => {
    entry.status = 'queued';
    entry.loaded = 0;
    entry.token = null;
    entry.error = null;
    updateFileRow(entry);
  });
  updateTotalProgress();

  try {
    const response = await requestApproval(requestEntries);
    session = parseApproval(response);

    requestEntries.forEach((entry) => {
      const token = session.files[entry.id];
      entry.token = typeof token === 'string' ? token : null;
      entry.status = entry.token ? 'queued' : 'skipped';
      updateFileRow(entry);
    });
    updateTotalProgress();

    if (!requestEntries.some((entry) => entry.token)) {
      finishTransfer();
      return;
    }

    await uploadAcceptedFiles();
  } catch (error) {
    handleTransferError(error);
  }
}

function handleTransferError(error) {
  const transferError = error instanceof TransferError
    ? error
    : new TransferError('prepare', 0, t.networkError);

  if (transferError.kind === 'prepare' || transferError.kind === 'pin-canceled') {
    entries.filter((entry) => entry.status === 'awaiting').forEach((entry) => {
      entry.status = 'queued';
      updateFileRow(entry);
    });
  }

  if (transferError.kind === 'session') {
    session = null;
  }

  setHeroStatus(transferError.message);
  showNotice(transferError.message);
  elements.progressTitle.textContent = t.failed;
  elements.sendButton.hidden = true;
  elements.retryButton.hidden = false;
  elements.newTransferButton.hidden = Boolean(session);
  retryMode = transferError.kind === 'upload' && session ? 'upload' : 'prepare-pending';
  setLocked(false);
  elements.sendButton.hidden = true;
  elements.retryButton.hidden = false;
  elements.newTransferButton.hidden = Boolean(session);
}

async function retryTransfer() {
  if (locked) return;
  elements.retryButton.hidden = true;
  elements.newTransferButton.hidden = true;
  showNotice('');

  if (retryMode === 'upload' && session) {
    setLocked(true);
    entries.filter((entry) => entry.status === 'failed').forEach((entry) => {
      entry.status = 'queued';
      entry.loaded = 0;
      updateFileRow(entry);
    });
    try {
      await uploadAcceptedFiles();
    } catch (error) {
      handleTransferError(error);
    }
    return;
  }

  session = null;
  setLocked(false);
  await beginTransfer(true);
}

function newTransfer() {
  if (locked && !elements.newTransferButton.hidden) {
    locked = false;
  }
  entries = [];
  selectionFrozen = false;
  session = null;
  retryMode = 'prepare';
  renderFileList();
  resetTransferUi();
  setLocked(false);
  updateSummary();
}

function isFileDrag(event) {
  return Array.from(event.dataTransfer?.types || []).includes('Files');
}

function bindEvents() {
  elements.pickFiles.addEventListener('click', (event) => {
    event.stopPropagation();
    elements.fileInput.click();
  });
  elements.pickFolder.addEventListener('click', (event) => {
    event.stopPropagation();
    elements.folderInput.click();
  });
  elements.dropZone.addEventListener('click', (event) => {
    if (!event.target.closest('button') && !locked) elements.fileInput.click();
  });
  elements.dropZone.addEventListener('keydown', (event) => {
    if (!locked && (event.key === 'Enter' || event.key === ' ')) {
      event.preventDefault();
      elements.fileInput.click();
    }
  });

  elements.fileInput.addEventListener('change', () => {
    addFiles(filesFromInput(elements.fileInput.files));
    elements.fileInput.value = '';
  });
  elements.folderInput.addEventListener('change', () => {
    addFiles(filesFromInput(elements.folderInput.files));
    elements.folderInput.value = '';
  });

  let dragDepth = 0;
  elements.dropZone.addEventListener('dragenter', (event) => {
    if (!isFileDrag(event) || locked) return;
    event.preventDefault();
    dragDepth += 1;
    elements.dropZone.classList.add('is-dragging');
  });
  elements.dropZone.addEventListener('dragover', (event) => {
    if (!isFileDrag(event) || locked) return;
    event.preventDefault();
    event.dataTransfer.dropEffect = 'copy';
  });
  elements.dropZone.addEventListener('dragleave', () => {
    dragDepth = Math.max(0, dragDepth - 1);
    if (!dragDepth) elements.dropZone.classList.remove('is-dragging');
  });
  elements.dropZone.addEventListener('drop', async (event) => {
    if (!isFileDrag(event) || locked) return;
    event.preventDefault();
    dragDepth = 0;
    elements.dropZone.classList.remove('is-dragging');
    setHeroStatus(t.readingFolder);
    try {
      const files = await filesFromDrop(event.dataTransfer);
      if (!files.length && Array.from(event.dataTransfer.items || []).some((item) => item.kind === 'file')) {
        showNotice(t.folderUnsupported);
      } else {
        addFiles(files);
      }
    } catch (_) {
      showNotice(t.folderUnsupported);
      setHeroStatus(t.initialStatus);
    }
  });

  elements.sendButton.addEventListener('click', () => beginTransfer(false));
  elements.retryButton.addEventListener('click', retryTransfer);
  elements.newTransferButton.addEventListener('click', newTransfer);
}

applyStaticCopy();
bindEvents();
updateSummary();
