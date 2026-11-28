const { spawn } = require('child_process');
const EventEmitter = require('events');
const fs = require('fs');
const path = require('path');
const { normalizeWindowsPath } = require('./config');

class AcpClient extends EventEmitter {
  constructor(options) {
    super();
    this.agyBin = options.agyBin;
    this.defaultCwd = options.defaultCwd;
    this.autoApproveAll = Boolean(options.autoApproveAll);
    this.onAutoApproveChange = typeof options.onAutoApproveChange === 'function' ? options.onAutoApproveChange : null;
    this.proc = null;
    this.buffer = '';
    this.nextId = 1;
    this.pending = new Map(); // id -> { resolve, reject, method }
    this.initialized = false;
    this.agentInfo = { name: 'Antigravity ACP Server', version: '' };
    this.authMethods = [];
    this.tierName = null;
    this.pendingPermissions = new Map(); // requestId -> { rpcId, sessionId, toolCall, options, createdAt }
    this.sessionsState = new Map(); // sessionId -> { sessionId, cwd, title, configOptions, availableCommands, messages, usage, isGenerating }
    this.loadingSessions = new Set();
    this.activeSessionId = null;
    this.restarting = false;
  }

  start() {
    if (this.proc) return Promise.resolve();

    return new Promise((resolve, reject) => {
      console.log(`[acp] Launching: ${this.agyBin} acp`);
      const child = spawn(this.agyBin, ['acp'], {
        cwd: this.defaultCwd,
        stdio: ['pipe', 'pipe', 'pipe'],
        windowsHide: true
      });

      this.proc = child;
      this.buffer = '';

      child.stdout.on('data', (chunk) => this._onStdout(chunk));
      child.stderr.on('data', (chunk) => {
        const text = chunk.toString('utf8').trim();
        if (text) console.error(`[acp stderr] ${text}`);
      });

      child.on('error', (err) => {
        console.error('[acp] Process error:', err.message);
        this.initialized = false;
        this.proc = null;
        this._rejectAllPending(err);
        reject(err);
      });

      child.on('exit', (code, signal) => {
        console.warn(`[acp] Process exited (code=${code}, signal=${signal})`);
        this.initialized = false;
        this.proc = null;
        this._rejectAllPending(new Error(`ACP process exited (${code || signal})`));
        for (const state of this.sessionsState.values()) {
          state.isGenerating = false;
        }
        this.emit('disconnected', { code, signal });
      });

      // Perform ACP v1 initialize handshake
      this.request('initialize', {
        protocolVersion: 1,
        clientCapabilities: {
          fs: { readTextFile: false, writeTextFile: false },
          terminal: false
        },
        clientInfo: {
          name: 'antigravity-ios-remote',
          version: '1.0.0'
        }
      })
        .then((res) => {
          this.initialized = true;
          this.agentInfo = res.agentInfo || this.agentInfo;
          this.authMethods = res.authMethods || [];
          console.log(`[acp] Initialized: ${this.agentInfo.name} v${this.agentInfo.version || '?'}`);
          resolve(res);
        })
        .catch((err) => {
          reject(err);
        });
    });
  }

  async ensureStarted() {
    if (this.proc && this.initialized) return;
    if (this.restarting) {
      await new Promise((r) => setTimeout(r, 800));
      if (this.proc && this.initialized) return;
    }
    this.restarting = true;
    try {
      await this.start();
    } finally {
      this.restarting = false;
    }
  }

  _rejectAllPending(err) {
    for (const { reject } of this.pending.values()) {
      reject(err);
    }
    this.pending.clear();
  }

  _sendRaw(obj) {
    if (!this.proc || !this.proc.stdin.writable) {
      throw new Error('Antigravity ACP process is not running');
    }
    this.proc.stdin.write(JSON.stringify(obj) + '\n');
  }

  request(method, params = {}) {
    return new Promise((resolve, reject) => {
      const id = this.nextId++;
      this.pending.set(id, { resolve, reject, method });
      try {
        this._sendRaw({ jsonrpc: '2.0', id, method, params });
      } catch (err) {
        this.pending.delete(id);
        reject(err);
      }
    });
  }

  notify(method, params = {}) {
    this._sendRaw({ jsonrpc: '2.0', method, params });
  }

  _onStdout(chunk) {
    this.buffer += chunk.toString('utf8');
    let idx;
    while ((idx = this.buffer.indexOf('\n')) !== -1) {
      const line = this.buffer.slice(0, idx).trim();
      this.buffer = this.buffer.slice(idx + 1);
      if (!line) continue;
      let msg;
      try {
        msg = JSON.parse(line);
      } catch (err) {
        console.warn('[acp] Non-JSON line:', line.slice(0, 200));
        continue;
      }
      this._handleMessage(msg);
    }
  }

  _handleMessage(msg) {
    // 1. Response to our outgoing JSON-RPC request
    if (msg.id !== undefined && !msg.method) {
      const entry = this.pending.get(msg.id);
      if (entry) {
        this.pending.delete(msg.id);
        if (msg.error) {
          const err = new Error(msg.error.message || JSON.stringify(msg.error));
          err.code = msg.error.code;
          entry.reject(err);
        } else {
          entry.resolve(msg.result);
        }
      }
      return;
    }

    // 2. Agent-initiated permission request
    if (msg.method === 'session/request_permission') {
      this._handlePermissionRequest(msg);
      return;
    }

    // 3. Session update notification
    if (msg.method === 'session/update') {
      this._handleSessionUpdate(msg.params);
      return;
    }

    // 4. Unknown incoming request — reply with method not found so agent doesn't hang
    if (msg.id !== undefined && msg.method) {
      this._sendRaw({
        jsonrpc: '2.0',
        id: msg.id,
        error: { code: -32601, message: `Unsupported client method: ${msg.method}` }
      });
    }
  }

  _getOrCreateSessionState(sessionId, cwd) {
    let state = this.sessionsState.get(sessionId);
    if (!state) {
      state = {
        sessionId,
        cwd: normalizeWindowsPath(cwd || this.defaultCwd),
        title: 'New Chat',
        configOptions: [],
        availableCommands: this._withBridgeCommands([]),
        messages: [],
        usage: { used: 0, size: 1048576 },
        isGenerating: false
      };
      this.sessionsState.set(sessionId, state);
    }
    return state;
  }

  _ensureAssistantMessage(state) {
    const last = state.messages[state.messages.length - 1];
    if (last && last.role === 'assistant' && last.streaming) {
      return last;
    }
    const msg = {
      id: `ast_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`,
      role: 'assistant',
      text: '',
      thought: '',
      toolCalls: [],
      streaming: true,
      timestamp: Date.now()
    };
    state.messages.push(msg);
    return msg;
  }

  _formatToolInput(tc) {
    const raw = tc.rawInput || tc.args || {};
    if (raw.CommandLine) return raw.CommandLine;
    if (raw.Path) return raw.Path;
    if (raw.TargetFile) return raw.TargetFile;
    if (raw.query) return raw.query;
    if (raw.Url) return raw.Url;
    const keys = Object.keys(raw);
    if (!keys.length) return tc.title || '';
    try {
      const s = JSON.stringify(raw, null, 2);
      return s.length > 600 ? s.slice(0, 600) + '...' : s;
    } catch (_) {
      return tc.title || '';
    }
  }

  _formatToolOutput(tc) {
    if (tc.rawOutput && typeof tc.rawOutput.output === 'string') {
      const out = tc.rawOutput.output;
      return out.length > 4000 ? out.slice(0, 4000) + '\n... [truncated]' : out;
    }
    if (Array.isArray(tc.content)) {
      const parts = [];
      for (const item of tc.content) {
        if (item && item.content && typeof item.content.text === 'string') {
          parts.push(item.content.text);
        } else if (item && typeof item.text === 'string') {
          parts.push(item.text);
        }
      }
      if (parts.length) {
        const out = parts.join('\n');
        return out.length > 4000 ? out.slice(0, 4000) + '\n... [truncated]' : out;
      }
    }
    return '';
  }

  _withBridgeCommands(commands = []) {
    const list = Array.isArray(commands) ? [...commands] : [];
    if (!list.some((c) => c && c.name === 'auto-approve')) {
      list.push({
        name: 'auto-approve',
        description: 'Bật/tắt tự động duyệt mọi lệnh (/auto-approve on | off)'
      });
    }
    return list;
  }

  _pickAllowOption(options = []) {
    return (
      options.find((o) => String(o.kind || '').toLowerCase() === 'allow_always') ||
      options.find((o) => !String(o.kind || '').toLowerCase().startsWith('reject')) ||
      options[0] ||
      null
    );
  }

  setAutoApproveAll(enabled) {
    this.autoApproveAll = Boolean(enabled);
    if (this.onAutoApproveChange) {
      this.onAutoApproveChange(this.autoApproveAll);
    }
    if (this.autoApproveAll && this.pendingPermissions.size > 0) {
      for (const [reqId, entry] of Array.from(this.pendingPermissions.entries())) {
        const allowOpt = this._pickAllowOption(entry.options);
        if (allowOpt) {
          this.respondPermission(reqId, allowOpt.optionId, false);
        }
      }
    }
    return this.autoApproveAll;
  }

  _handleLocalCommand(sessionId, state, text) {
    const match = String(text || '').trim().match(/^(?:\/auto-approve|\/auto)(?:\s+(\S+))?\s*$/i);
    if (!match) return false;

    const arg = (match[1] || 'status').toLowerCase();
    let replyText;

    if (arg === 'on' || arg === 'true' || arg === '1' || arg === 'enable') {
      this.setAutoApproveAll(true);
      replyText = '✅ Đã **BẬT** chế độ tự động duyệt mọi lệnh (`autoApproveAll = true`).\nTừ giờ các yêu cầu chạy lệnh hoặc sửa file sẽ được Bridge Server tự động chấp nhận và đã lưu vào `bridge-config.json`.\n\nGõ `/auto-approve off` nếu muốn quay lại chế độ hỏi duyệt thủ công.';
    } else if (arg === 'off' || arg === 'false' || arg === '0' || arg === 'disable') {
      this.setAutoApproveAll(false);
      replyText = '🛡️ Đã **TẮT** chế độ tự động duyệt (`autoApproveAll = false`).\nBridge Server sẽ gửi yêu cầu duyệt lệnh về iPhone như bình thường.\n\nGõ `/auto-approve on` để bật lại bất kỳ lúc nào.';
    } else if (arg === 'status') {
      replyText = `⚙️ Trạng thái tự động duyệt lệnh hiện tại: **${this.autoApproveAll ? 'ĐANG BẬT (ON)' : 'ĐANG TẮT (OFF)'}**.\n\nCách dùng:\n- \`/auto-approve on\` — Bật tự động duyệt mọi lệnh\n- \`/auto-approve off\` — Tắt, quay lại hỏi duyệt thủ công`;
    } else {
      replyText = `⚠️ Tham số không hợp lệ: \`${arg}\`.\n\nCách dùng:\n- \`/auto-approve on\` — Bật tự động duyệt mọi lệnh\n- \`/auto-approve off\` — Tắt tự động duyệt\n- \`/auto-approve\` — Xem trạng thái hiện tại`;
    }

    const now = Date.now();
    state.messages.push({
      id: `usr_${now}_${Math.random().toString(36).slice(2, 7)}`,
      role: 'user',
      text: String(text).trim(),
      thought: '',
      toolCalls: [],
      imageCount: 0,
      streaming: false,
      timestamp: now
    });
    state.messages.push({
      id: `ast_${now + 1}_${Math.random().toString(36).slice(2, 7)}`,
      role: 'assistant',
      text: replyText,
      thought: '',
      toolCalls: [],
      streaming: false,
      timestamp: now + 1
    });

    this.activeSessionId = sessionId;
    this.emit('turn_started', { sessionId });
    this.emit('message_chunk', { sessionId, role: 'assistant', text: replyText });
    this.emit('turn_finished', { sessionId, stopReason: 'end_turn', usage: state.usage || null });
    return true;
  }

  _handlePermissionRequest(msg) {
    const params = msg.params || {};
    const sessionId = params.sessionId || this.activeSessionId || '';
    const tc = params.toolCall || {};
    const requestId = `perm_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`;

    const payload = {
      requestId,
      rpcId: msg.id,
      sessionId,
      toolCall: {
        toolCallId: tc.toolCallId || requestId,
        name: tc.name || 'tool',
        title: tc.title || tc.name || 'Tool action',
        kind: tc.kind || 'execute',
        inputSummary: this._formatToolInput(tc)
      },
      options: (params.options || []).map((o) => ({
        optionId: o.optionId,
        name: o.name || o.optionId,
        kind: o.kind || 'allow_once'
      })),
      createdAt: Date.now()
    };

    if (!payload.options.length) {
      payload.options = [
        { optionId: 'allow', name: 'Allow', kind: 'allow_once' },
        { optionId: 'deny', name: 'Deny', kind: 'reject_once' }
      ];
    }

    if (this.autoApproveAll) {
      const allowOpt = this._pickAllowOption(payload.options);
      if (allowOpt) {
        console.log(`[acp] Auto-approved "${payload.toolCall.name}" (${allowOpt.optionId})`);
        this._sendRaw({
          jsonrpc: '2.0',
          id: msg.id,
          result: { outcome: { outcome: 'selected', optionId: allowOpt.optionId } }
        });
        return;
      }
    }

    this.pendingPermissions.set(requestId, payload);
    this.emit('permission_request', {
      requestId: payload.requestId,
      sessionId: payload.sessionId,
      toolCall: payload.toolCall,
      options: payload.options
    });
  }

  respondPermission(requestId, optionId, cancelled = false) {
    const entry = this.pendingPermissions.get(requestId);
    if (!entry) return false;
    this.pendingPermissions.delete(requestId);

    const outcome = cancelled || !optionId
      ? { outcome: 'cancelled' }
      : { outcome: 'selected', optionId };

    this._sendRaw({
      jsonrpc: '2.0',
      id: entry.rpcId,
      result: { outcome }
    });

    this.emit('permission_resolved', {
      requestId,
      sessionId: entry.sessionId,
      optionId: optionId || null,
      cancelled: Boolean(cancelled)
    });
    return true;
  }

  _handleSessionUpdate(params) {
    if (!params || !params.update) return;
    const sessionId = params.sessionId || this.activeSessionId;
    if (!sessionId) return;

    const state = this._getOrCreateSessionState(sessionId);
    const isReplaying = this.loadingSessions.has(sessionId);
    const u = params.update;
    const kind = u.sessionUpdate;

    if (kind === 'agent_message_chunk') {
      const text = (u.content && u.content.text) || '';
      if (!text) return;
      const msg = this._ensureAssistantMessage(state);
      msg.text += text;
      if (!isReplaying) this.emit('message_chunk', { sessionId, role: 'assistant', text });
      return;
    }

    if (kind === 'agent_thought_chunk' || kind === 'agent_thought') {
      const text = (u.content && u.content.text) || u.text || '';
      if (!text) return;
      const msg = this._ensureAssistantMessage(state);
      msg.thought += text;
      if (!isReplaying) this.emit('message_chunk', { sessionId, role: 'thought', text });
      return;
    }

    if (kind === 'user_message_chunk') {
      const text = (u.content && u.content.text) || '';
      if (!text) return;
      const last = state.messages[state.messages.length - 1];
      if (last && last.role === 'user' && last.replaying) {
        last.text += text;
      } else {
        // Close any open assistant bubble before adding replayed user message
        if (last && last.role === 'assistant') last.streaming = false;
        state.messages.push({
          id: `usr_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`,
          role: 'user',
          text,
          thought: '',
          toolCalls: [],
          replaying: true,
          streaming: false,
          timestamp: Date.now()
        });
      }
      if (!isReplaying) this.emit('message_chunk', { sessionId, role: 'user', text });
      return;
    }

    if (kind === 'tool_call' || kind === 'tool_call_update') {
      const msg = this._ensureAssistantMessage(state);
      const tcId = u.toolCallId || `tc_${Date.now()}`;
      const normalized = {
        toolCallId: tcId,
        name: u.name || 'tool',
        title: u.title || u.name || 'Tool',
        kind: u.kind || 'other',
        status: u.status || 'in_progress',
        inputSummary: this._formatToolInput(u),
        outputText: this._formatToolOutput(u)
      };
      const existingIdx = msg.toolCalls.findIndex((t) => t.toolCallId === tcId);
      if (existingIdx >= 0) {
        msg.toolCalls[existingIdx] = {
          ...msg.toolCalls[existingIdx],
          ...normalized,
          inputSummary: normalized.inputSummary || msg.toolCalls[existingIdx].inputSummary,
          outputText: normalized.outputText || msg.toolCalls[existingIdx].outputText
        };
      } else {
        msg.toolCalls.push(normalized);
      }
      if (!isReplaying) {
        this.emit('tool_call', { sessionId, toolCall: existingIdx >= 0 ? msg.toolCalls[existingIdx] : normalized });
      }
      return;
    }

    if (kind === 'session_info_update') {
      if (u.title) state.title = u.title;
      this.emit('session_meta', { sessionId, title: state.title });
      return;
    }

    if (kind === 'usage_update') {
      state.usage = { used: Number(u.used || 0), size: Number(u.size || 1048576) };
      this.emit('session_meta', { sessionId, usage: state.usage });
      return;
    }

    if (kind === 'config_option_update' && Array.isArray(u.configOptions)) {
      state.configOptions = u.configOptions;
      this.emit('session_meta', { sessionId, configOptions: state.configOptions });
      return;
    }

    if (kind === 'current_mode_update' && u.currentModeId) {
      const modeOpt = state.configOptions.find((c) => c.id === 'mode');
      if (modeOpt) modeOpt.currentValue = u.currentModeId;
      this.emit('session_meta', { sessionId, configOptions: state.configOptions });
      return;
    }

    if (kind === 'available_commands_update' && Array.isArray(u.availableCommands)) {
      state.availableCommands = this._withBridgeCommands(
        u.availableCommands.map((c) => ({
          name: c.name,
          description: c.description || ''
        }))
      );
      this.emit('session_meta', { sessionId, availableCommands: state.availableCommands });
    }
  }

  async listSessions() {
    await this.ensureStarted();
    const res = await this.request('session/list', {});
    const sessions = (res && Array.isArray(res.sessions) ? res.sessions : []).map((s) => ({
      sessionId: s.sessionId,
      cwd: normalizeWindowsPath(s.cwd || this.defaultCwd),
      title: s.title || 'Untitled Chat',
      updatedAt: s.updatedAt || ''
    }));
    sessions.sort((a, b) => (b.updatedAt || '').localeCompare(a.updatedAt || ''));
    return sessions;
  }

  async newSession(cwd) {
    await this.ensureStarted();
    const targetCwd = normalizeWindowsPath(cwd || this.defaultCwd);
    const validCwd = fs.existsSync(targetCwd) ? targetCwd : this.defaultCwd;
    const res = await this.request('session/new', {
      cwd: validCwd,
      mcpServers: []
    });
    const sessionId = res.sessionId;
    if (res._meta && res._meta.antigravity && res._meta.antigravity.tier) {
      this.tierName = res._meta.antigravity.tier.name || this.tierName;
    }
    const state = this._getOrCreateSessionState(sessionId, validCwd);
    state.cwd = validCwd;
    state.configOptions = res.configOptions || [];
    this.activeSessionId = sessionId;
    return state;
  }

  async loadSession(sessionId, cwd) {
    await this.ensureStarted();
    const existing = this.sessionsState.get(sessionId);
    if (existing && existing.messages.length > 0) {
      this.activeSessionId = sessionId;
      return existing;
    }

    const targetCwd = normalizeWindowsPath(cwd || (existing && existing.cwd) || this.defaultCwd);
    const validCwd = fs.existsSync(targetCwd) ? targetCwd : this.defaultCwd;

    // Reset replay buffer for clean history load
    const state = this._getOrCreateSessionState(sessionId, validCwd);
    state.messages = [];
    state.cwd = validCwd;
    this.loadingSessions.add(sessionId);

    let res;
    try {
      res = await this.request('session/load', {
        sessionId,
        cwd: validCwd,
        mcpServers: []
      });
    } catch (loadErr) {
      this.loadingSessions.delete(sessionId);
      // Desktop GUI App conversations cannot be resumed directly by agy acp (-32002).
      // Start a clean ACP session in the exact same workspace folder instead of failing on prompt!
      const fresh = await this.newSession(validCwd);
      fresh.messages.push({
        id: `sys_${Date.now()}`,
        role: 'assistant',
        text: `ℹ️ Cuộc trò chuyện cũ này thuộc cửa sổ **Antigravity Desktop App** nên không thể nối trực tiếp từ \`agy acp\`. Đã tự động mở **phiên mới** tại cùng thư mục \`${fresh.cwd}\` để bạn điều khiển ngay!`,
        thought: '',
        toolCalls: [],
        streaming: false,
        timestamp: Date.now()
      });
      return fresh;
    } finally {
      this.loadingSessions.delete(sessionId);
    }

    this.activeSessionId = sessionId;

    // Finalize replayed messages
    for (const m of state.messages) {
      m.streaming = false;
      delete m.replaying;
    }
    if (res && Array.isArray(res.configOptions) && res.configOptions.length) {
      state.configOptions = res.configOptions;
    }
    return state;
  }

  async sendPrompt(sessionId, text, images = []) {
    await this.ensureStarted();
    let sid = sessionId || this.activeSessionId;
    if (!sid) {
      const created = await this.newSession(this.defaultCwd);
      sid = created.sessionId;
    }

    const state = this._getOrCreateSessionState(sid);
    if ((!Array.isArray(images) || images.length === 0) && this._handleLocalCommand(sid, state, text)) {
      return { stopReason: 'end_turn', localCommand: true };
    }
    // Close any prior streaming bubble
    for (const m of state.messages) m.streaming = false;

    const promptBlocks = [];
    if (text && text.trim()) {
      promptBlocks.push({ type: 'text', text: text.trim() });
    }
    if (Array.isArray(images)) {
      for (const img of images) {
        if (img && img.data && img.mimeType) {
          promptBlocks.push({
            type: 'image',
            data: img.data,
            mimeType: img.mimeType
          });
        }
      }
    }
    if (!promptBlocks.length) {
      throw new Error('Prompt cannot be empty');
    }

    // Append user turn to local transcript
    state.messages.push({
      id: `usr_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`,
      role: 'user',
      text: text ? text.trim() : '[Image]',
      thought: '',
      toolCalls: [],
      imageCount: Array.isArray(images) ? images.length : 0,
      streaming: false,
      timestamp: Date.now()
    });

    state.isGenerating = true;
    this.activeSessionId = sid;
    this.emit('turn_started', { sessionId: sid });

    try {
      let res;
      try {
        res = await this.request('session/prompt', {
          sessionId: sid,
          prompt: promptBlocks
        });
      } catch (promptErr) {
        // Auto-recover if a stale/Desktop trajectory is no longer available in agy acp
        if (/trajectory not found|session not found/i.test(promptErr.message || '')) {
          console.warn(`[acp] Stale session ${sid}, auto-creating fresh session in ${state.cwd}`);
          const fresh = await this.newSession(state.cwd);
          sid = fresh.sessionId;
          fresh.messages.push({
            id: `usr_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`,
            role: 'user',
            text: text ? text.trim() : '[Image]',
            thought: '',
            toolCalls: [],
            imageCount: Array.isArray(images) ? images.length : 0,
            streaming: false,
            timestamp: Date.now()
          });
          fresh.isGenerating = true;
          this.emit('session_ready', {
            sessionId: fresh.sessionId,
            cwd: fresh.cwd,
            title: fresh.title,
            configOptions: fresh.configOptions,
            availableCommands: fresh.availableCommands,
            messages: fresh.messages,
            usage: fresh.usage,
            isGenerating: true
          });
          res = await this.request('session/prompt', {
            sessionId: sid,
            prompt: promptBlocks
          });
          fresh.isGenerating = false;
          for (const m of fresh.messages) m.streaming = false;
          this.emit('turn_finished', {
            sessionId: sid,
            stopReason: (res && res.stopReason) || 'end_turn',
            usage: (res && res.usage) || null
          });
          return res;
        }
        throw promptErr;
      }
      state.isGenerating = false;
      for (const m of state.messages) m.streaming = false;
      this.emit('turn_finished', {
        sessionId: sid,
        stopReason: (res && res.stopReason) || 'end_turn',
        usage: (res && res.usage) || null
      });
      return res;
    } catch (err) {
      state.isGenerating = false;
      for (const m of state.messages) m.streaming = false;
      this.emit('turn_finished', {
        sessionId: sid,
        stopReason: 'error',
        error: err.message
      });
      throw err;
    }
  }

  cancel(sessionId) {
    const sid = sessionId || this.activeSessionId;
    if (!sid || !this.proc) return;
    // Cancel any pending permission requests for this session
    for (const [reqId, entry] of this.pendingPermissions.entries()) {
      if (entry.sessionId === sid) {
        this.respondPermission(reqId, null, true);
      }
    }
    this.notify('session/cancel', { sessionId: sid });
  }

  async setConfigOption(sessionId, configId, value) {
    await this.ensureStarted();
    const sid = sessionId || this.activeSessionId;
    if (!sid) throw new Error('No active session');
    const res = await this.request('session/set_config_option', {
      sessionId: sid,
      configId,
      value
    });
    const state = this._getOrCreateSessionState(sid);
    if (res && Array.isArray(res.configOptions)) {
      state.configOptions = res.configOptions;
    } else {
      const opt = state.configOptions.find((c) => c.id === configId);
      if (opt) opt.currentValue = value;
    }
    this.emit('session_meta', { sessionId: sid, configOptions: state.configOptions });
    return state.configOptions;
  }

  getActiveSnapshot() {
    const state = this.activeSessionId ? this.sessionsState.get(this.activeSessionId) : null;
    const pendingPermissions = Array.from(this.pendingPermissions.values()).map((p) => ({
      requestId: p.requestId,
      sessionId: p.sessionId,
      toolCall: p.toolCall,
      options: p.options
    }));

    return {
      activeSessionId: this.activeSessionId,
      activeCwd: state ? state.cwd : this.defaultCwd,
      activeTitle: state ? state.title : 'New Chat',
      configOptions: state ? state.configOptions : [],
      availableCommands: this._withBridgeCommands(state ? state.availableCommands : []),
      messages: state ? state.messages : [],
      usage: state ? state.usage : { used: 0, size: 1048576 },
      isGenerating: state ? state.isGenerating : false,
      pendingPermissions
    };
  }
}

module.exports = { AcpClient };
