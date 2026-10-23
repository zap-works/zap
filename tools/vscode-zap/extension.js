// The Zap extension's client: it starts `zap lsp` (the language server inside the compiler),
// speaks the Language Server Protocol with it, and restarts it whenever the compiler is
// rebuilt, so the editor follows the language as it changes: the grammar colours the keywords,
// types, calls and fields wherever the code is shown (a diff too), and the server's semantic tokens
// refine them in a file (a variant, a module, an option). The server runs from a copy of
// the executable in the extension's storage: the build can then replace build/zap.exe while the
// editor uses it. No dependencies: the protocol it needs is small and written out here.
const vscode = require('vscode');
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

let server = null;          // { proc, pending, nextId, buffer }
let watched = null;
let restartTimer = null;
let storage = '';
let output = null;
let diagnostics = null;
let tokensProvider = null;  // the semantic tokens' registration, made with the server's legend

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

function send(message) {
  if (!server) {
    return;
  }
  const body = Buffer.from(JSON.stringify({ jsonrpc: '2.0', ...message }), 'utf8');
  server.proc.stdin.write(`Content-Length: ${body.length}\r\n\r\n`);
  server.proc.stdin.write(body);
}

function request(method, params) {
  if (!server) {
    return Promise.resolve(null);
  }
  const id = server.nextId++;
  return new Promise((resolve) => {
    server.pending.set(id, resolve);
    send({ id, method, params });
  });
}

function notify(method, params) {
  send({ method, params });
}

function received(chunk) {
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
    handle(JSON.parse(body));
  }
}

function handle(message) {
  if (message.id !== undefined && server.pending.has(message.id)) {
    const resolve = server.pending.get(message.id);
    server.pending.delete(message.id);
    resolve(message.result);
  } else if (message.method === 'textDocument/publishDiagnostics') {
    const uri = vscode.Uri.parse(message.params.uri);
    diagnostics.set(uri, message.params.diagnostics.map((d) => {
      const item = new vscode.Diagnostic(toRange(d.range), d.message, vscode.DiagnosticSeverity.Error);
      item.source = 'zap';
      return item;
    }));
  }
}

// ---------- the server's life ----------

async function start() {
  const compiler = compilerPath();
  if (!fs.existsSync(compiler)) {
    output.appendLine(`zap: no compiler at ${compiler} (build it, or set zap.compilerPath)`);
    return;
  }
  const proc = spawn(serverCopy(compiler), ['lsp'], {
    cwd: workspaceRoot() || undefined,
    env: { ...process.env, ZAP_RUN: `runtime=${runtimePath(compiler)}${process.env.ZAP_RUN ? "," + process.env.ZAP_RUN : ""}` },
  });
  server = { proc, pending: new Map(), nextId: 1, buffer: Buffer.alloc(0) };
  proc.stdout.on('data', received);
  proc.stderr.on('data', (d) => output.append(d.toString()));
  proc.on('exit', (code) => {
    if (server && server.proc === proc) {
      output.appendLine(`zap: the language server stopped (${code})`);
      server = null;
    }
  });
  const root = workspaceRoot();
  const answer = await request('initialize', { processId: process.pid, rootUri: root ? vscode.Uri.file(root).toString() : null, capabilities: {} });
  notify('initialized', {});
  registerTokens(answer && answer.capabilities.semanticTokensProvider);
  for (const doc of vscode.workspace.textDocuments) {
    opened(doc);
  }
  output.appendLine(`zap: language server started from ${compiler}`);
  watch(compiler);
}

async function stop() {
  if (!server) {
    return;
  }
  const old = server;
  await Promise.race([request('shutdown', null), new Promise((r) => setTimeout(r, 1000))]);
  notify('exit', null);
  server = null;
  setTimeout(() => old.proc.kill(), 500);
}

async function restart() {
  await stop();
  await start();
}

// a new build of the compiler restarts the server (once the file has stopped changing)
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
      output.appendLine('zap: the compiler changed, restarting the language server');
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
      const tokens = await request('textDocument/semanticTokens/full', { textDocument: textDocument(doc) });
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
    notify('textDocument/didOpen', { textDocument: { uri: doc.uri.toString(), languageId: 'zap', version: doc.version, text: doc.getText() } });
  }
}

function textDocument(doc) {
  return { uri: doc.uri.toString() };
}

// ---------- answers, from the protocol's shapes to the editor's ----------

function toRange(r) {
  return new vscode.Range(r.start.line, r.start.character, r.end.line, r.end.character);
}

function toSymbol(s) {
  const kind = Math.max(0, (s.kind || 1) - 1);   // the protocol counts kinds from 1, the editor from 0
  const symbol = new vscode.DocumentSymbol(s.name, s.detail || '', kind, toRange(s.range), toRange(s.selectionRange));
  symbol.children = (s.children || []).map(toSymbol);
  return symbol;
}

function toLocation(l) {
  return new vscode.Location(vscode.Uri.parse(l.uri), toRange(l.range));
}

function at(doc, position) {
  return { textDocument: textDocument(doc), position: { line: position.line, character: position.character } };
}

exports.activate = async function (context) {
  storage = context.globalStorageUri.fsPath;
  output = vscode.window.createOutputChannel('Zap');
  diagnostics = vscode.languages.createDiagnosticCollection('zap');
  const selector = [{ scheme: 'file', language: 'zap' }, { scheme: 'file', language: 'zapx' }];
  context.subscriptions.push(
    output,
    diagnostics,
    vscode.commands.registerCommand('zap.restartServer', restart),
    vscode.workspace.onDidOpenTextDocument(opened),
    vscode.workspace.onDidChangeTextDocument((e) => {
      if (isZap(e.document)) {
        notify('textDocument/didChange', { textDocument: { uri: e.document.uri.toString(), version: e.document.version }, contentChanges: [{ text: e.document.getText() }] });
      }
    }),
    vscode.workspace.onDidSaveTextDocument((doc) => isZap(doc) && notify('textDocument/didSave', { textDocument: textDocument(doc) })),
    vscode.workspace.onDidCloseTextDocument((doc) => isZap(doc) && notify('textDocument/didClose', { textDocument: textDocument(doc) })),
    vscode.languages.registerDocumentSymbolProvider(selector, {
      async provideDocumentSymbols(doc) {
        return ((await request('textDocument/documentSymbol', { textDocument: textDocument(doc) })) || []).map(toSymbol);
      },
    }),
    vscode.languages.registerWorkspaceSymbolProvider({
      async provideWorkspaceSymbols(query) {
        const found = (await request('workspace/symbol', { query })) || [];
        return found.map((s) => new vscode.SymbolInformation(s.name, Math.max(0, s.kind - 1), s.containerName || '', toLocation(s.location)));
      },
    }),
    vscode.languages.registerReferenceProvider(selector, {
      async provideReferences(doc, position, context) {
        const found = (await request('textDocument/references', { ...at(doc, position), context: { includeDeclaration: context.includeDeclaration } })) || [];
        return found.map(toLocation);
      },
    }),
    vscode.languages.registerDefinitionProvider(selector, {
      async provideDefinition(doc, position) {
        return ((await request('textDocument/definition', at(doc, position))) || []).map(toLocation);
      },
    }),
    vscode.languages.registerDocumentFormattingEditProvider(selector, {
      async provideDocumentFormattingEdits(doc) {
        const edits = (await request('textDocument/formatting', { textDocument: textDocument(doc), options: {} })) || [];
        return edits.map((e) => vscode.TextEdit.replace(toRange(e.range), e.newText));
      },
    }),
    vscode.languages.registerHoverProvider(selector, {
      async provideHover(doc, position) {
        const hover = await request('textDocument/hover', at(doc, position));
        return hover ? new vscode.Hover(new vscode.MarkdownString(hover.contents.value)) : null;
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
