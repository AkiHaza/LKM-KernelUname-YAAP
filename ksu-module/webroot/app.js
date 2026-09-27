(() => {
  'use strict';

  const moduleDir = '/data/adb/modules/yaap-kernelmask';
  const serviceFile = `${moduleDir}/service.sh`;
  const ids = ['release', 'version'];
  let callbackCounter = 0;

  function quote(value) {
    return `'${String(value).replace(/'/g, "'\\''")}'`;
  }

  function exec(command) {
    const bridge = window.ksu || (typeof ksu !== 'undefined' ? ksu : null);
    if (!bridge || typeof bridge.exec !== 'function') {
      throw new Error('KernelSU WebUI bridge unavailable');
    }

    return new Promise((resolve, reject) => {
      const callbackName = `kernelmask_exec_${Date.now()}_${callbackCounter++}`;
      window[callbackName] = (errno, stdout, stderr) => {
        delete window[callbackName];
        if (Number(errno) !== 0) {
          reject(new Error(stderr || stdout || `Command failed: ${errno}`));
        } else {
          resolve(stdout || '');
        }
      };

      try {
        bridge.exec(command, JSON.stringify({}), callbackName);
      } catch (error) {
        delete window[callbackName];
        reject(error);
      }
    });
  }

  function setMessage(text, error = false) {
    const node = document.querySelector('#message');
    node.textContent = text;
    node.style.color = error ? '#f85149' : '#56d364';
  }

  async function refresh() {
    const command = [
      `printf '%s\\n' '--- module ---'`,
      `grep '^kernelmask ' /proc/modules 2>/dev/null || printf '%s\\n' 'kernelmask: not loaded'`,
      `cat /sys/module/kernelmask/parameters/applied 2>/dev/null || true`,
      `printf '%s\\n' '--- uname -a ---'`,
      `uname -a`,
      `printf '%s\\n' '--- uname -r / -v ---'`,
      `uname -r`,
      `uname -v`,
      `printf '%s\\n' '--- /proc/sys/kernel/osrelease ---'`,
      `cat /proc/sys/kernel/osrelease 2>/dev/null || true`,
      `printf '%s\\n' '--- /proc/sys/kernel/version ---'`,
      `cat /proc/sys/kernel/version 2>/dev/null || true`,
      `printf '%s\\n' '--- /proc/version ---'`,
      `cat /proc/version 2>/dev/null || true`,
      `printf '%s\\n' '--- parameters ---'`,
      `for f in enabled release version; do printf '%s=' "$f"; cat "/sys/module/kernelmask/parameters/$f" 2>/dev/null || true; done`,
      `printf '%s\\n' '--- log ---'`,
      `tail -n 12 /data/adb/kernelmask/service.log 2>/dev/null || true`,
    ].join('; ');
    document.querySelector('#status').textContent = await exec(command);
  }

  async function loadConfig() {
    let output;
    try {
      output = await exec(`sh ${quote(serviceFile)} --read-config`);
    } catch (error) {
      document.querySelector('#enabled').checked = false;
      ids.forEach((id) => { document.querySelector(`#${id}`).value = ''; });
      setMessage(`配置损坏或无法读取：${error.message}`, true);
      return;
    }
    const values = {};
    output.split(/\r?\n/).forEach((line) => {
      const index = line.indexOf('=');
      if (index > 0) values[line.slice(0, index)] = line.slice(index + 1);
    });
    document.querySelector('#enabled').checked = /^(?:1|y|Y|true|TRUE)$/.test(values.enabled || '');
    ids.forEach((id) => { document.querySelector(`#${id}`).value = values[id] || ''; });
  }

  async function save() {
    const values = {};
    ids.forEach((id) => { values[id] = document.querySelector(`#${id}`).value; });
    for (const value of Object.values(values)) {
      if (value.length > 64 || /[^\x20-\x7e]|['"\\]/.test(value)) {
        throw new Error('字段只能包含安全的 ASCII 字符，最长 64 字符');
      }
    }
    if (values.release.includes(' ')) {
      throw new Error('内核版本标识不能包含空格');
    }
    const lines = [
      `enabled=${document.querySelector('#enabled').checked ? '1' : '0'}`,
      ...ids.map((id) => `${id}=${values[id]}`),
    ];
    const body = lines.map((line) => `printf '%s\\n' ${quote(line)}`).join('; ');
    const command = `{ ${body}; } | sh ${quote(serviceFile)} --save-config`;
    try {
      await exec(command);
    } catch (error) {
      await loadConfig();
      await refresh();
      throw error;
    }
    setMessage('已保存并重载');
    await refresh();
  }

  document.querySelector('#refresh').addEventListener('click', () => refresh().catch((e) => setMessage(e.message, true)));
  document.querySelector('#save').addEventListener('click', () => save().catch((e) => setMessage(e.message, true)));
  Promise.all([loadConfig(), refresh()]).catch((e) => setMessage(e.message, true));
})();
