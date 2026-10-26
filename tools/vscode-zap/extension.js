// The Zap extension's client: it starts `zap lsp` (the language server inside the compiler),
// speaks the Language Server Protocol with it, and restarts it whenever the compiler is
// rebuilt, so the editor follows the language as it changes: the grammar colours the keywords,
// types, calls and fields wherever the code is shown (a diff too), and the server's semantic tokens
// refine them in a file (a variant, a module, an option). Two servers run: one answers from the
// text alone (outline, symbols, definitions, references, formatting, colours) and never waits;
// the other checks the program a file belongs to when it is saved and answers from what the
// checker found (errors, the inferred types shown after the bindings, a name's type on hover,
// what follows `x.`). While it checks, hover and completion take the first server's answer.
// Each runs from a copy of the executable in the extension's storage: the build can then replace
// build/zap.exe while the editor uses it. No dependencies: the protocol it needs is small and
// written out here. The server counts columns in bytes; the client turns them into the editor's.
const vscode = require('vscode');
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

const servers = { text: null, checks: null };   // each { role, proc, pending, nextId, buffer }
let stopping = false;
let restarts = [];          // when the servers last stopped on their own (a crash), to stop retrying
let watched = null;
let restartTimer = null;
let storage = '';
let output = null;
let diagnostics = null;
let tokensProvider = null;  // the semantic tokens' registration, made with the server's legend
let hintsChanged = null;    // fired when a check ends: its types replace the hints shown
const checkWaitMs = 400;    // how long hover and completion wait for the checker before the text's answer

// ---------- where the compiler is ----------

function workspaceRoot() {
  const folders = vscode.workspace.workspaceFolders || [];
  return folders.length > 0 ? folders[0].uri.fsPath : '';
}

// the compiler built in the zap repository: build/zap.exe when the workspace is that repository,
// zap/build/zap.exe when it is the folder holding it (each workspace folder in turn)
function compilerPath() {
  const configured = vscode.workspace.getConfiguration('zap').get('compilerPath');
  if (configured) {
    return configured;
  }
  const folders = (vscode.workspace.workspaceFolders || []).map((f) => f.uri.fsPath);
  for (const folder of folders) {
    for (const candidate of [
      path.join(folder, 'build', 'zap.exe'),
      path.join(folder, 'zap', 'build', 'zap.exe'),
    ]) {
      if (fs.existsSync(candidate)) {
        return candidate;
      }
    }
  }
  return path.join(workspaceRoot(), 'zap', 'build', 'zap.exe');
}

function runtimePath(compiler) {
  const configured = vscode.workspace.getConfiguration('zap').get('runtimePath');
  return configured || path.join(path.dirname(path.dirname(compiler)), 'runtime');
}

// a copy of the compiler named after its modification time; older copies not in use are removed
function serverCopy(compiler) {
  fs.mkdirSync(storage, { recursive: true });
  const stamp = Math.floor(fs.statSync(compiler).mtimeMs);
  const copy = path.join(storage, `zap-lsp-${stamp}.exe`);
  if (!fs.existsSync(copy)) {
    fs.copyFileSync(compiler, copy);
  }
  for (const name of fs.readdirSync(storage)) {
    const old = path.join(storage, name);
    if (name.startsWith('zap-lsp-') && old !== copy) {
      try {
        fs.unlinkSync(old);
      } catch {
        // still running: removed next time
      }
    }
  }
  return copy;
}

// ---------- the protocol: JSON messages with a Content-Length header ----------

function send(server, message) {
  if (!server) {
    return;
  }
  const body = Buffer.from(JSON.stringify({ jsonrpc: '2.0', ...message }), 'utf8');
  server.proc.stdin.write(`Content-Length: ${body.length}\r\n\r\n`);
  server.proc.stdin.write(body);
}

function request(server, method, params) {
  if (!server) {
    return Promise.resolve(null);
  }
  const id = server.nextId++;
  return new Promise((resolve) => {
    server.pending.set(id, resolve);
    send(server, { id, method, params });
  });
}

// the checker's answer, or the text server's when the checker is busy (a check under way)
async function checkedOrText(method, params) {
  const late = Symbol('late');
  const checked = await Promise.race([
    request(servers.checks, method, params),
    new Promise((r) => setTimeout(() => r(late), checkWaitMs)),
  ]);
  return checked !== late ? checked : request(servers.text, method, params);
}

function notifyBoth(method, params) {
  send(servers.text, { method, params });
  send(servers.checks, { method, params });
}

function received(server, chunk) {
  server.buffer = Buffer.concat([server.buffer, chunk]);
  for (;;) {
    const end = server.buffer.indexOf('\r\n\r\n');
    if (end < 0) {
      return;
    }
    const header = server.buffer.slice(0, end).toString('ascii');
    const match = /Content-Length: *(\d+)/i.exec(header);
    const length = match ? Number(match[1]) : 0;
    if (server.buffer.length < end + 4 + length) {
      return;
    }
    const body = server.buffer.slice(end + 4, end + 4 + length).toString('utf8');
    server.buffer = server.buffer.slice(end + 4 + length);
    handle(server, JSON.parse(body));
  }
}

function handle(server, message) {
  if (message.id !== undefined && server.pending.has(message.id)) {
    const resolve = server.pending.get(message.id);
    server.pending.delete(message.id);
    resolve(message.result);
  } else if (message.method === 'textDocument/publishDiagnostics') {
    const uri = vscode.Uri.parse(message.params.uri);
    const doc = openDocument(uri);
    diagnostics.set(uri, message.params.diagnostics.map((d) => {
      const item = new vscode.Diagnostic(toRange(d.range, doc), d.message, vscode.DiagnosticSeverity.Error);
      item.source = 'zap';
      return item;
    }));
    hintsChanged.fire();
  }
}

// ---------- the servers' life ----------

// one server: the text's (`checks: false`, never checks) or the checker's
async function startServer(role, compiler) {
  const proc = spawn(serverCopy(compiler), ['lsp'], {
    cwd: workspaceRoot() || undefined,
    env: { ...process.env, ZAP_RUN: `runtime=${runtimePath(compiler)}${process.env.ZAP_RUN ? "," + process.env.ZAP_RUN : ""}` },
  });
  const server = { role, proc, pending: new Map(), nextId: 1, buffer: Buffer.alloc(0) };
  servers[role] = server;
  proc.stdout.on('data', (chunk) => received(server, chunk));
  proc.stderr.on('data', (d) => output.append(d.toString()));
  proc.on('exit', (code) => {
    if (servers[role] !== server) {
      return;
    }
    servers[role] = null;
    for (const resolve of server.pending.values()) {
      resolve(null);
    }
    output.appendLine(`zap: the ${role} server stopped (${code})`);
    if (!stopping) {
      crashed(role);
    }
  });
  const root = workspaceRoot();
  const answer = await request(server, 'initialize', {
    processId: process.pid,
    rootUri: root ? vscode.Uri.file(root).toString() : null,
    capabilities: {},
    initializationOptions: { checks: role === 'checks' },
  });
  send(server, { method: 'initialized', params: {} });
  for (const doc of vscode.workspace.textDocuments) {
    if (isZap(doc)) {
      send(server, { method: 'textDocument/didOpen', params: { textDocument: { uri: doc.uri.toString(), languageId: 'zap', version: doc.version, text: doc.getText() } } });
    }
  }
  return answer;
}

// a server that stopped on its own is started again, unless it keeps stopping
function crashed(role) {
  const now = Date.now();
  restarts = restarts.filter((t) => now - t < 60000);
  restarts.push(now);
  if (restarts.length > 5) {
    output.appendLine('zap: the language server keeps stopping; run "Zap: Restart Language Server" once fixed');
    return;
  }
  setTimeout(() => {
    const compiler = compilerPath();
    if (!servers[role] && !stopping && fs.existsSync(compiler)) {
      startServer(role, compiler);
    }
  }, 1000);
}

async function start() {
  const compiler = compilerPath();
  if (!fs.existsSync(compiler)) {
    output.appendLine(`zap: no compiler at ${compiler} (build it, or set zap.compilerPath)`);
    return;
  }
  stopping = false;
  const answer = await startServer('text', compiler);
  await startServer('checks', compiler);
  registerTokens(answer && answer.capabilities.semanticTokensProvider);
  output.appendLine(`zap: language servers started from ${compiler}`);
  watch(compiler);
}

async function stopServer(server) {
  if (!server) {
    return;
  }
  await Promise.race([request(server, 'shutdown', null), new Promise((r) => setTimeout(r, 1000))]);
  send(server, { method: 'exit', params: null });
  setTimeout(() => server.proc.kill(), 500);
}

async function stop() {
  stopping = true;
  const old = [servers.text, servers.checks];
  servers.text = null;
  servers.checks = null;
  await Promise.all(old.map(stopServer));
}

async function restart() {
  await stop();
  await start();
}

// a new build of the compiler restarts the servers (once the file has stopped changing)
function watch(compiler) {
  if (watched === compiler) {
    return;
  }
  if (watched) {
    fs.unwatchFile(watched);
  }
  watched = compiler;
  fs.watchFile(compiler, { interval: 1500 }, (now, before) => {
    if (now.mtimeMs === before.mtimeMs || now.size === 0) {
      return;
    }
    clearTimeout(restartTimer);
    restartTimer = setTimeout(() => {
      output.appendLine('zap: the compiler changed, restarting the language servers');
      restart();
    }, 2000);
  });
}

// the semantic tokens, with the legend the server announced (it may change with the compiler)
function registerTokens(provider) {
  if (tokensProvider) {
    tokensProvider.dispose();
    tokensProvider = null;
  }
  if (!provider) {
    return;
  }
  const legend = new vscode.SemanticTokensLegend(provider.legend.tokenTypes, provider.legend.tokenModifiers);
  tokensProvider = vscode.languages.registerDocumentSemanticTokensProvider([{ scheme: 'file', language: 'zap' }, { scheme: 'file', language: 'zapx' }], {
    async provideDocumentSemanticTokens(doc) {
      const tokens = await request(servers.text, 'textDocument/semanticTokens/full', { textDocument: textDocument(doc) });
      return new vscode.SemanticTokens(new Uint32Array(tokens ? tokens.data : []));
    },
  }, legend);
}

// ---------- documents ----------

function isZap(doc) {
  return (doc.languageId === 'zap' || doc.languageId === 'zapx') && doc.uri.scheme === 'file';
}

function opened(doc) {
  if (isZap(doc)) {
    notifyBoth('textDocument/didOpen', { textDocument: { uri: doc.uri.toString(), languageId: 'zap', version: doc.version, text: doc.getText() } });
  }
}

function openDocument(uri) {
  return vscode.workspace.textDocuments.find((d) => d.uri.toString() === uri.toString());
}

function textDocument(doc) {
  return { uri: doc.uri.toString() };
}

// ---------- columns: the server's bytes, the editor's UTF-16 units ----------

function toChars(doc, line, bytes) {
  if (!doc || line >= doc.lineCount) {
    return bytes;
  }
  return Buffer.from(doc.lineAt(line).text, 'utf8').slice(0, bytes).toString('utf8').length;
}

function toBytes(doc, position) {
  if (position.line >= doc.lineCount) {
    return position.character;
  }
  return Buffer.byteLength(doc.lineAt(position.line).text.slice(0, position.character), 'utf8');
}

// ---------- answers, from the protocol's shapes to the editor's ----------

function toPosition(p, doc) {
  return new vscode.Position(p.line, toChars(doc, p.line, p.character));
}

function toRange(r, doc) {
  return new vscode.Range(toPosition(r.start, doc), toPosition(r.end, doc));
}

function toSymbol(s, doc) {
  const kind = Math.max(0, (s.kind || 1) - 1);   // the protocol counts kinds from 1, the editor from 0
  const symbol = new vscode.DocumentSymbol(s.name, s.detail || '', kind, toRange(s.range, doc), toRange(s.selectionRange, doc));
  symbol.children = (s.children || []).map((c) => toSymbol(c, doc));
  return symbol;
}

function toLocation(l) {
  const uri = vscode.Uri.parse(l.uri);
  return new vscode.Location(uri, toRange(l.range, openDocument(uri)));
}

function at(doc, position) {
  return { textDocument: textDocument(doc), position: { line: position.line, character: toBytes(doc, position) } };
}

exports.activate = async function (context) {
  storage = context.globalStorageUri.fsPath;
  output = vscode.window.createOutputChannel('Zap');
  diagnostics = vscode.languages.createDiagnosticCollection('zap');
  hintsChanged = new vscode.EventEmitter();
  const selector = [{ scheme: 'file', language: 'zap' }, { scheme: 'file', language: 'zapx' }];
  context.subscriptions.push(
    output,
    diagnostics,
    hintsChanged,
    vscode.commands.registerCommand('zap.restartServer', restart),
    vscode.workspace.onDidOpenTextDocument(opened),
    vscode.workspace.onDidChangeTextDocument((e) => {
      if (isZap(e.document) && e.contentChanges.length > 0) {
        notifyBoth('textDocument/didChange', { textDocument: { uri: e.document.uri.toString(), version: e.document.version }, contentChanges: [{ text: e.document.getText() }] });
      }
    }),
    vscode.workspace.onDidSaveTextDocument((doc) => isZap(doc) && notifyBoth('textDocument/didSave', { textDocument: textDocument(doc) })),
    vscode.workspace.onDidCloseTextDocument((doc) => isZap(doc) && notifyBoth('textDocument/didClose', { textDocument: textDocument(doc) })),
    vscode.languages.registerDocumentSymbolProvider(selector, {
      async provideDocumentSymbols(doc) {
        return ((await request(servers.text, 'textDocument/documentSymbol', { textDocument: textDocument(doc) })) || []).map((s) => toSymbol(s, doc));
      },
    }),
    vscode.languages.registerWorkspaceSymbolProvider({
      async provideWorkspaceSymbols(query) {
        const found = (await request(servers.text, 'workspace/symbol', { query })) || [];
        return found.map((s) => new vscode.SymbolInformation(s.name, Math.max(0, s.kind - 1), s.containerName || '', toLocation(s.location)));
      },
    }),
    vscode.languages.registerReferenceProvider(selector, {
      async provideReferences(doc, position, context) {
        const found = (await request(servers.text, 'textDocument/references', { ...at(doc, position), context: { includeDeclaration: context.includeDeclaration } })) || [];
        return found.map(toLocation);
      },
    }),
    vscode.languages.registerDefinitionProvider(selector, {
      async provideDefinition(doc, position) {
        return ((await request(servers.text, 'textDocument/definition', at(doc, position))) || []).map(toLocation);
      },
    }),
    vscode.languages.registerDocumentFormattingEditProvider(selector, {
      async provideDocumentFormattingEdits(doc) {
        const edits = (await request(servers.text, 'textDocument/formatting', { textDocument: textDocument(doc), options: {} })) || [];
        return edits.map((e) => vscode.TextEdit.replace(toRange(e.range, doc), e.newText));
      },
    }),
    vscode.languages.registerHoverProvider(selector, {
      async provideHover(doc, position) {
        const hover = await checkedOrText('textDocument/hover', at(doc, position));
        return hover ? new vscode.Hover(new vscode.MarkdownString(hover.contents.value)) : null;
      },
    }),
    vscode.languages.registerCompletionItemProvider(selector, {
      async provideCompletionItems(doc, position) {
        const items = (await checkedOrText('textDocument/completion', at(doc, position))) || [];
        return items.map((i) => {
          const item = new vscode.CompletionItem(i.label, Math.max(0, (i.kind || 1) - 1));
          item.detail = i.detail || undefined;
          item.sortText = `${i.kind === 5 ? 0 : 1}${i.label}`;   // the fields first, then the functions
          return item;
        });
      },
    }, '.'),
    vscode.languages.registerInlayHintsProvider(selector, {
      onDidChangeInlayHints: hintsChanged.event,
      async provideInlayHints(doc, range) {
        const hints = (await request(servers.checks, 'textDocument/inlayHint', {
          textDocument: textDocument(doc),
          range: { start: { line: range.start.line, character: 0 }, end: { line: range.end.line, character: 0 } },
        })) || [];
        return hints.map((h) => {
          const hint = new vscode.InlayHint(toPosition(h.position, doc), h.label, h.kind);
          hint.paddingLeft = !!h.paddingLeft;
          return hint;
        });
      },
    }),
  );
  await start();
};

exports.deactivate = async function () {
  if (watched) {
    fs.unwatchFile(watched);
  }
  registerTokens(null);
  await stop();
};
