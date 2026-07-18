// LocalShare keeps this file in legacy JavaScript syntax so older LAN browsers
// can still use the download page. File bodies are downloaded by the browser,
// never buffered in JavaScript.

var BASE_URL = '/api/localsend/v2';
var DOWNLOAD_QUEUE_DELAY = 850;
var DOWNLOAD_FRAME_LIFETIME = 5 * 60 * 1000;

var COPY = {
  en: {
    networkLabel: 'Local network',
    readyTitle: 'Files ready to download',
    sharedFilesTitle: 'Shared files',
    directLabel: 'Direct from the sender',
    footerLabel: 'You can also download any file individually.',
    batchTitle: 'Download this batch',
    downloadAll: 'Download all',
    downloadAgain: 'Download again',
    startingArchive: 'Starting ZIP download…',
    archiveStarted: 'ZIP download started. Keep this page open until it finishes.',
    startingDownloads: 'Starting downloads…',
    bulkHelp: 'All files are streamed directly from the sender in one ZIP archive.',
    fileSingular: 'file',
    filePlural: 'files',
    downloadFile: 'Download',
    waiting: 'Waiting for the sender…',
    rejected: 'The sender declined this request.',
    tooManyAttempts: 'Too many attempts. Please wait and try again.',
    enterPin: 'Enter the PIN shown by the sender.',
    invalidPin: 'That PIN is not valid.',
    files: 'Files',
    error: 'Could not load the shared files',
    allStartedPrefix: 'All',
    allStartedSuffix: 'downloads were started. Check your browser\'s downloads.'
  },
  zh: {
    networkLabel: '局域网直连',
    readyTitle: '文件已准备好',
    sharedFilesTitle: '共享文件',
    directLabel: '直接来自发送端',
    footerLabel: '也可以随时点击下方任一文件单独下载。',
    batchTitle: '下载本批文件',
    downloadAll: '全部下载',
    downloadAgain: '重新下载',
    startingArchive: '正在启动 ZIP 下载…',
    archiveStarted: 'ZIP 下载已开始，请保持此页面打开直到下载完成。',
    startingDownloads: '正在启动下载…',
    bulkHelp: '全部文件会从发送端直接流式写入一个 ZIP 压缩包。',
    fileSingular: '个文件',
    filePlural: '个文件',
    downloadFile: '下载',
    waiting: '正在等待发送端确认…',
    rejected: '发送端拒绝了本次请求。',
    tooManyAttempts: '尝试次数过多，请稍后再试。',
    enterPin: '请输入发送端显示的 PIN。',
    invalidPin: 'PIN 不正确。',
    files: '文件',
    error: '无法加载共享文件',
    allStartedPrefix: '已启动全部',
    allStartedSuffix: '项下载，请在浏览器下载列表中查看。'
  }
};

var copy = COPY.en;
var isChinese = false;
var useServerProtocolCopy = true;
var i18n = createFallbackI18n();
var sessionId = getStoredSessionId();
var queryParams = location.search.slice(1).split('&');
var queryPin = null;
var downloadableFiles = [];
var archiveDownloadUrl = null;
var downloadQueueRunning = false;
var downloadFrameSequence = 0;

// Parse query parameters manually for older browsers.
for (var i = 0; i < queryParams.length; i++) {
  var pair = queryParams[i].split('=');
  if (pair[0] === 'pin') {
    try {
      queryPin = decodeURIComponent(pair[1] || '');
    } catch (error) {
      queryPin = pair[1] || '';
    }
    break;
  }
}

function firstRequestFiles() {
  setText('status-text', i18n.waiting);
  var initialUrl = BASE_URL + '/prepare-download';

  if (sessionId) {
    initialUrl += '?sessionId=' + encodeURIComponent(sessionId);
    if (queryPin) {
      initialUrl += '&pin=' + encodeURIComponent(queryPin);
    }
  } else if (queryPin) {
    initialUrl += '?pin=' + encodeURIComponent(queryPin);
  }

  makeRequest(initialUrl, 'POST', function (response) {
    if (response.status === 401) {
      pinRequestFiles(true);
      return;
    }

    if (response.status === 403) {
      setText('status-text', i18n.rejected);
      return;
    }

    if (response.status === 429) {
      setText('status-text', i18n.tooManyAttempts);
      return;
    }

    if (response.status !== 200) {
      setText('status-text', i18n.error + ' (' + response.status + ')');
      return;
    }

    handleSuccess(response);
  });
}

function pinRequestFiles(firstAttempt) {
  var pin = prompt(i18n.enterPin + (firstAttempt ? '' : '\n' + i18n.invalidPin));
  if (!pin) {
    setText('status-text', i18n.invalidPin);
    return;
  }

  makeRequest(BASE_URL + '/prepare-download?pin=' + encodeURIComponent(pin), 'POST', function (response) {
    if (response.status === 401) {
      pinRequestFiles(false);
      return;
    }

    if (response.status === 403) {
      setText('status-text', i18n.rejected);
      return;
    }

    if (response.status === 429) {
      setText('status-text', i18n.tooManyAttempts);
      return;
    }

    if (response.status !== 200) {
      setText('status-text', i18n.error + ' (' + response.status + ')');
      return;
    }

    handleSuccess(response);
  });
}

function makeRequest(url, method, callback) {
  var xhr = new XMLHttpRequest();
  xhr.open(method, url, true);
  xhr.onreadystatechange = function () {
    if (xhr.readyState === 4) {
      callback(xhr);
    }
  };
  xhr.send();
}

function fetchI18n(then) {
  makeRequest('/i18n.json', 'GET', function (response) {
    if (response.status === 200 && useServerProtocolCopy) {
      try {
        var serverCopy = JSON.parse(response.responseText);
        mergeI18n(serverCopy);
      } catch (error) {
        // The static fallback keeps the page usable if localization is invalid.
      }
    }
    then();
  });
}

function mergeI18n(serverCopy) {
  if (!serverCopy) {
    return;
  }

  var keys = getKeys(serverCopy);
  for (var i = 0; i < keys.length; i++) {
    i18n[keys[i]] = serverCopy[keys[i]];
  }
}

function createFallbackI18n() {
  return {
    waiting: copy.waiting,
    rejected: copy.rejected,
    tooManyAttempts: copy.tooManyAttempts,
    enterPin: copy.enterPin,
    invalidPin: copy.invalidPin,
    files: copy.files,
    error: copy.error
  };
}

function init() {
  applyStaticCopy();
  bindDownloadControls();
  fetchI18n(firstRequestFiles);
}

function applyStaticCopy() {
  var language = (navigator.language || navigator.userLanguage || '').toLowerCase();
  isChinese = language.indexOf('zh') === 0;
  useServerProtocolCopy = language === '' || (!isChinese && language.indexOf('en') !== 0);
  copy = isChinese ? COPY.zh : COPY.en;
  i18n = createFallbackI18n();

  if (isChinese) {
    document.documentElement.lang = 'zh-CN';
  }

  setText('network-label', copy.networkLabel);
  setText('ready-title', copy.readyTitle);
  setText('shared-files-title', copy.sharedFilesTitle);
  setText('direct-label', copy.directLabel);
  setText('footer-label', copy.footerLabel);
  setText('bulk-title', copy.batchTitle);
  setText('download-all-label', copy.downloadAll);
  setText('bulk-help', copy.bulkHelp);
}

function bindDownloadControls() {
  addEvent(document.getElementById('download-all-button'), 'click', beginDownloadAll);
}

function handleSuccess(response) {
  var data;
  try {
    data = JSON.parse(response.responseText);
  } catch (error) {
    setText('status-text', i18n.error);
    return;
  }

  var files = data.files || {};
  sessionId = data.sessionId;
  storeSessionId(sessionId);

  setText('status-text', i18n.files + ' (' + getKeys(files).length + ')');
  handleFilesDisplay(files, sessionId);
}

function handleFilesDisplay(files, activeSessionId) {
  var fileList = document.getElementById('file-list');
  var singleFile = document.getElementById('single-file');
  var fileKeys = getKeys(files);

  clearElement(fileList);
  clearElement(singleFile);
  downloadableFiles = [];
  archiveDownloadUrl = fileKeys.length > 1
      ? BASE_URL + '/download-all?sessionId=' + encodeURIComponent(activeSessionId)
      : null;

  for (var i = 0; i < fileKeys.length; i++) {
    var fileId = fileKeys[i];
    var file = files[fileId] || {};
    var fileName = file.fileName === null || typeof file.fileName === 'undefined'
        ? i18n.files + ' ' + (i + 1)
        : String(file.fileName);
    var size = normalizeSize(file.size);
    var downloadUrl = BASE_URL + '/download?sessionId=' + encodeURIComponent(activeSessionId) +
        '&fileId=' + encodeURIComponent(fileId);
    var item = {
      fileName: fileName,
      size: size,
      url: downloadUrl
    };

    downloadableFiles.push(item);

    var link = document.createElement('a');
    link.className = 'file-item';
    link.href = downloadUrl;
    link.title = copy.downloadFile + ': ' + fileName;
    link.setAttribute('aria-label', copy.downloadFile + ' ' + fileName + ', ' + formatBytes(size));
    link.appendChild(createFileCell('file-index-cell', String(i + 1)));
    link.appendChild(createFileCell('file-name-cell', fileName));
    link.appendChild(createFileCell('file-size-cell', formatBytes(size)));

    if (fileKeys.length === 1) {
      singleFile.appendChild(link);
    } else {
      fileList.appendChild(link);
    }
  }

  updateBulkDownloadControl();
}

function createFileCell(className, value) {
  var cell = document.createElement('div');
  cell.className = className;
  cell.appendChild(document.createTextNode(value));
  return cell;
}

function updateBulkDownloadControl() {
  var bulkDownload = document.getElementById('bulk-download');
  var shouldShow = downloadableFiles.length > 1;
  setElementHidden(bulkDownload, !shouldShow);

  if (!shouldShow) {
    return;
  }

  var totalSize = 0;
  for (var i = 0; i < downloadableFiles.length; i++) {
    totalSize += downloadableFiles[i].size;
  }

  setText('bulk-meta', formatFileCount(downloadableFiles.length) + ' · ' + formatBytes(totalSize));
}

function beginDownloadAll() {
  if (downloadQueueRunning || downloadableFiles.length < 2) {
    return;
  }

  downloadQueueRunning = true;
  var button = document.getElementById('download-all-button');
  button.disabled = true;
  setElementHidden(document.getElementById('bulk-progress'), false);

  if (archiveDownloadUrl) {
    setText('download-all-label', copy.startingArchive);
    setText('bulk-progress-status', copy.startingArchive);
    setText('bulk-progress-count', 'ZIP');
    updateProgress(1, 1);
    if (triggerArchiveDownload(archiveDownloadUrl)) {
      window.setTimeout(finishArchiveDownload, 350);
      return;
    }
  }

  // Very old browsers that cannot synthesize a single archive download keep
  // the previous sequential behavior as a compatibility fallback.
  setText('download-all-label', copy.startingDownloads);
  startQueuedDownload(0);
}

function triggerArchiveDownload(url) {
  var link = document.createElement('a');
  link.href = url;
  link.style.display = 'none';
  link.setAttribute('download', 'LocalShare-files.zip');
  link.setAttribute('aria-hidden', 'true');
  document.body.appendChild(link);

  try {
    if (typeof link.click === 'function') {
      link.click();
    } else if (document.createEvent) {
      var clickEvent = document.createEvent('MouseEvents');
      clickEvent.initMouseEvent('click', true, true, window, 1, 0, 0, 0, 0,
          false, false, false, false, 0, null);
      link.dispatchEvent(clickEvent);
    } else {
      removeNode(link);
      return false;
    }
  } catch (error) {
    removeNode(link);
    return false;
  }

  removeNode(link);
  return true;
}

function startQueuedDownload(index) {
  var total = downloadableFiles.length;
  if (index >= total) {
    finishDownloadQueue();
    return;
  }

  var item = downloadableFiles[index];
  var position = index + 1;
  setText('bulk-progress-status', formatStartingMessage(position, total, item.fileName));
  setText('bulk-progress-count', position + ' / ' + total);
  triggerBrowserDownload(item);
  updateProgress(position, total);

  if (position === total) {
    window.setTimeout(finishDownloadQueue, 350);
  } else {
    window.setTimeout(function () {
      startQueuedDownload(index + 1);
    }, DOWNLOAD_QUEUE_DELAY);
  }
}

function triggerBrowserDownload(item) {
  downloadFrameSequence += 1;
  var frameName = 'localshare-download-' + new Date().getTime() + '-' + downloadFrameSequence;
  var frame = document.createElement('iframe');
  frame.className = 'download-frame';
  frame.name = frameName;
  frame.id = frameName;
  frame.setAttribute('aria-hidden', 'true');
  document.body.appendChild(frame);

  var link = document.createElement('a');
  link.href = item.url;
  link.target = frameName;
  link.style.display = 'none';
  link.setAttribute('download', '');
  link.setAttribute('aria-hidden', 'true');
  document.body.appendChild(link);

  try {
    if (typeof link.click === 'function') {
      link.click();
    } else if (document.createEvent) {
      var clickEvent = document.createEvent('MouseEvents');
      clickEvent.initMouseEvent('click', true, true, window, 1, 0, 0, 0, 0,
          false, false, false, false, 0, null);
      link.dispatchEvent(clickEvent);
    } else {
      frame.src = item.url;
    }
  } catch (error) {
    frame.src = item.url;
  }

  removeNode(link);
  window.setTimeout(function () {
    removeNode(frame);
  }, DOWNLOAD_FRAME_LIFETIME);
}

function finishDownloadQueue() {
  var total = downloadableFiles.length;
  downloadQueueRunning = false;
  var button = document.getElementById('download-all-button');
  button.disabled = false;
  setText('download-all-label', copy.downloadAgain);
  setText('bulk-progress-status', formatFinishedMessage(total));
  setText('bulk-progress-count', total + ' / ' + total);
  updateProgress(total, total);
}

function finishArchiveDownload() {
  downloadQueueRunning = false;
  var button = document.getElementById('download-all-button');
  button.disabled = false;
  setText('download-all-label', copy.downloadAgain);
  setText('bulk-progress-status', copy.archiveStarted);
  setText('bulk-progress-count', 'ZIP');
  updateProgress(1, 1);
}

function updateProgress(position, total) {
  var percent = total > 0 ? Math.round(position * 100 / total) : 0;
  document.getElementById('bulk-progress-bar').style.width = percent + '%';
  document.getElementById('bulk-progress-track').setAttribute('aria-valuenow', String(percent));
}

function formatStartingMessage(position, total, fileName) {
  if (isChinese) {
    return '正将第 ' + position + '/' + total + ' 个文件交给浏览器：' + fileName;
  }
  return 'Sending ' + position + ' of ' + total + ' to your browser: ' + fileName;
}

function formatFinishedMessage(total) {
  if (isChinese) {
    return copy.allStartedPrefix + total + copy.allStartedSuffix;
  }
  return copy.allStartedPrefix + ' ' + total + ' ' + copy.allStartedSuffix;
}

function formatFileCount(count) {
  if (isChinese) {
    return count + copy.filePlural;
  }
  return count + ' ' + (count === 1 ? copy.fileSingular : copy.filePlural);
}

function formatBytes(bytes) {
  if (bytes < 1024) {
    return bytes + ' B';
  } else if (bytes < 1024 * 1024) {
    return (bytes / 1024).toFixed(1) + ' KB';
  } else if (bytes < 1024 * 1024 * 1024) {
    return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
  } else if (bytes < 1024 * 1024 * 1024 * 1024) {
    return (bytes / (1024 * 1024 * 1024)).toFixed(1) + ' GB';
  }
  return (bytes / (1024 * 1024 * 1024 * 1024)).toFixed(1) + ' TB';
}

function normalizeSize(size) {
  var value = Number(size);
  if (!isFinite(value) || value < 0) {
    return 0;
  }
  return value;
}

function setText(elementOrId, value) {
  var element = typeof elementOrId === 'string'
      ? document.getElementById(elementOrId)
      : elementOrId;
  if (!element) {
    return;
  }

  clearElement(element);
  element.appendChild(document.createTextNode(value === null || typeof value === 'undefined' ? '' : String(value)));
}

function clearElement(element) {
  while (element.firstChild) {
    element.removeChild(element.firstChild);
  }
}

function setElementHidden(element, hidden) {
  if (!element) {
    return;
  }

  var paddedClassName = ' ' + element.className + ' ';
  var hasHiddenClass = paddedClassName.indexOf(' is-hidden ') !== -1;
  if (hidden && !hasHiddenClass) {
    element.className += ' is-hidden';
  } else if (!hidden && hasHiddenClass) {
    element.className = paddedClassName.replace(' is-hidden ', ' ').replace(/^\s+|\s+$/g, '');
  }
}

function addEvent(element, eventName, handler) {
  if (!element) {
    return;
  }
  if (element.addEventListener) {
    element.addEventListener(eventName, handler, false);
  } else if (element.attachEvent) {
    element.attachEvent('on' + eventName, handler);
  } else {
    element['on' + eventName] = handler;
  }
}

function removeNode(node) {
  if (node && node.parentNode) {
    node.parentNode.removeChild(node);
  }
}

function getStoredSessionId() {
  try {
    return sessionStorage.getItem('sessionId');
  } catch (error) {
    return null;
  }
}

function storeSessionId(value) {
  try {
    sessionStorage.setItem('sessionId', value);
  } catch (error) {
    // Private browsing modes can disable storage; this request still works.
  }
}

function getKeys(obj) {
  var keys = [];
  for (var key in obj) {
    if (Object.prototype.hasOwnProperty.call(obj, key)) {
      keys.push(key);
    }
  }
  return keys;
}

init();
