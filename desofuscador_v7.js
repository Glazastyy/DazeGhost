const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const childProcess = require('node:child_process');
const os = require('node:os');

const MASK = 0xffffffff;
const rotl = (v, n) => ((v << n) | (v >>> (32 - n))) >>> 0;
const sha256 = b => crypto.createHash('sha256').update(b).digest('hex');

class LuaLiteralReader {
  constructor(buffer, offset = 0) { this.b = buffer; this.o = offset; }
  skip() {
    while (this.o < this.b.length) {
      const x = this.b[this.o];
      if (x === 32 || x === 9 || x === 10 || x === 13 || x === 44 || x === 59) this.o++;
      else break;
    }
  }
  parse() {
    this.skip();
    const c = this.b[this.o];
    if (c === 123) return this.table();
    if (c === 34 || c === 39) return this.string();
    const begin = this.o;
    while (this.o < this.b.length && ![32, 9, 10, 13, 44, 59, 125, 41].includes(this.b[this.o])) this.o++;
    const v = this.b.subarray(begin, this.o).toString('ascii');
    if (v === 'true') return true;
    if (v === 'false') return false;
    if (v === 'nil') return null;
    if (/^-?(?:0x[0-9a-f]+|\d+)$/.test(v)) return Number(v);
    throw new Error(`Literal inesperado em ${begin}: ${v.slice(0, 40)}`);
  }
  table() {
    this.o++;
    const values = [];
    while (true) {
      this.skip();
      if (this.b[this.o] === 125) { this.o++; return values; }
      if (this.o >= this.b.length) throw new Error('Tabela incompleta');
      values.push(this.parse());
    }
  }
  string() {
    const quote = this.b[this.o++];
    const bytes = [];
    while (this.o < this.b.length) {
      const x = this.b[this.o++];
      if (x === quote) return Buffer.from(bytes);
      if (x !== 92) { bytes.push(x); continue; }
      const e = this.b[this.o++];
      if (e >= 48 && e <= 57) {
        let digits = String.fromCharCode(e);
        for (let i = 0; i < 2 && this.b[this.o] >= 48 && this.b[this.o] <= 57; i++) digits += String.fromCharCode(this.b[this.o++]);
        const num = Number(digits);
        if (num > 255) throw new Error('Escape decimal inválido');
        bytes.push(num);
      } else if (e === 122) {
        while ([32, 9, 10, 13, 11, 12].includes(this.b[this.o])) this.o++;
      } else if (e === 120) {
        const v = this.b.subarray(this.o, this.o + 2).toString('ascii');
        bytes.push(parseInt(v, 16)); this.o += 2;
      } else {
        const escapes = { 97: 7, 98: 8, 102: 12, 110: 10, 114: 13, 116: 9, 118: 11, 10: 10, 13: 10 };
        bytes.push(escapes[e] ?? e);
      }
    }
    throw new Error('String incompleta');
  }
}

function readOuter(buffer) {
  const marker = Buffer.from('end)({');
  const start = buffer.indexOf(marker);
  if (start < 0) throw new Error('Formato externo não reconhecido');
  const r = new LuaLiteralReader(buffer, start + marker.length - 1);
  const p = r.parse();
  const i = r.parse();
  const args = [];
  for (let n = 0; n < 18; n++) args.push(r.parse());
  if (!Array.isArray(p) || !Array.isArray(i)) throw new Error('Estrutura externa inválida');
  return [p, i, ...args];
}

class BytecodeReader {
  constructor(b) { this.b = b; this.o = 32; }
  byte() { if (this.o >= this.b.length) throw new Error('Bytecode truncado'); return this.b[this.o++]; }
  number() {
    let n = 0;
    while (true) {
      const x = this.byte(); n = n * 128 + (x & 127);
      if (!Number.isSafeInteger(n)) throw new Error('Inteiro Lua fora do intervalo seguro');
      if (x & 128) return n;
    }
  }
  string() {
    const n = this.number();
    if (!n) return null;
    if (this.o + n - 1 > this.b.length) throw new Error('String de bytecode truncada');
    const s = this.b.subarray(this.o, this.o + n - 1);
    this.o += n - 1;
    return s;
  }
  proto() {
    const source = this.string();
    this.number(); this.number();
    const params = this.byte(); this.byte(); const stack = this.byte();
    const ncode = this.number();
    const code = [];
    for (let j = 0; j < ncode; j++) { code.push(this.b.readUInt32LE(this.o)); this.o += 4; }
    const nc = this.number();
    const constants = [];
    for (let j = 0; j < nc; j++) {
      const tag = this.byte();
      if (tag === 0) constants.push(null);
      else if (tag === 1) constants.push(false);
      else if (tag === 17) constants.push(true);
      else if (tag === 19) { constants.push(this.b.readDoubleLE(this.o)); this.o += 8; }
      else if (tag === 3) {
        const value = this.b.readBigInt64LE(this.o); this.o += 8;
        if (value > BigInt(Number.MAX_SAFE_INTEGER) || value < BigInt(Number.MIN_SAFE_INTEGER)) throw new Error('Constante inteira grande demais');
        constants.push(Number(value));
      } else if (tag === 4 || tag === 20) constants.push(this.string());
      else throw new Error(`Constante Lua desconhecida: ${tag}`);
    }
    const upvalues = this.number(); this.o += upvalues * 3;
    const children = [];
    const nchildren = this.number();
    for (let j = 0; j < nchildren; j++) children.push(this.proto());
    const lineInfoSize = this.number();
    const lineInfo = [];
    for (let j = 0; j < lineInfoSize; j++) lineInfo.push(this.number());
    const absLineInfo = this.number();
    this.o += absLineInfo * 8;
    const locals = this.number();
    const localNames = [];
    for (let j = 0; j < locals; j++) localNames.push({ name: this.string(), start: this.number(), end: this.number() });
    const names = this.number();
    const upvalueNames = [];
    for (let j = 0; j < names; j++) upvalueNames.push(this.string());
    return { source, params, stack, code, constants, children, lineInfo, localNames, upvalueNames };
  }
}

const OPCODE_NAMES = [
  'MOVE', 'LOADI', 'LOADF', 'LOADK', 'LOADKX', 'LOADFALSE', 'LFALSESKIP', 'LOADTRUE',
  'LOADNIL', 'GETUPVAL', 'SETUPVAL', 'GETTABUP', 'GETTABLE', 'GETI', 'GETFIELD',
  'SETTABUP', 'SETTABLE', 'SETI', 'SETFIELD', 'NEWTABLE', 'SELF', 'ADD', 'SUB', 'MUL',
  'MOD', 'POW', 'DIV', 'IDIV', 'BAND', 'BOR', 'BXOR', 'SHL', 'SHR', 'ADDK', 'SUBK',
  'MULK', 'MODK', 'POWK', 'DIVK', 'IDIVK', 'BANDK', 'BORK', 'BXORK', 'SHLI', 'SHRI',
  'ADDI', 'ADDK', 'MULK', 'MMBIN', 'MMBINI', 'MMBINK', 'UNM', 'BNOT', 'NOT', 'LEN',
  'CONCAT', 'CLOSE', 'TBC', 'JMP', 'EQ', 'LT', 'LE', 'EQK', 'EQI', 'LTI', 'LEI', 'GTI',
  'GEI', 'TEST', 'TESTSET', 'CALL', 'TAILCALL', 'RETURN', 'RETURN0', 'RETURN1', 'FORLOOP',
  'FORPREP', 'TFORPREP', 'TFORCALL', 'TFORLOOP', 'SETLIST', 'CLOSURE', 'VARARG',
  'VARARGPREP', 'EXTRAARG'
];

function formatLuaString(value) {
  const bytes = Buffer.from(value, 'latin1');
  let result = '';
  for (const byte of bytes) {
    if (byte === 34) result += '\\"';
    else if (byte === 92) result += '\\\\';
    else if (byte === 10) result += '\\n';
    else if (byte === 13) result += '\\r';
    else if (byte === 9) result += '\\t';
    else if (byte >= 32 && byte <= 126) result += String.fromCharCode(byte);
    else result += `\\${String(byte).padStart(3, '0')}`;
  }
  return `"${result}"`;
}

function formatConstant(value) {
  if (value === null) return 'nil';
  if (typeof value === 'boolean') return String(value);
  if (typeof value === 'number') return String(value);
  if (Buffer.isBuffer(value)) return formatLuaString(value.toString('latin1'));
  return formatLuaString(String(value));
}

function decodeInstruction(ins) {
  const op = ins & 127;
  return {
    op,
    name: OPCODE_NAMES[op] || `OP_${op}`,
    A: (ins >>> 7) & 255,
    k: (ins >>> 15) & 1,
    B: (ins >>> 16) & 255,
    C: (ins >>> 24) & 255,
    Bx: ins >>> 15,
    sBx: (ins >>> 15) - 65535,
    Ax: ins >>> 7
  };
}

function renderProto(proto, index = 0, output = []) {
  const title = proto.source ? proto.source.toString('latin1') : `proto_${index}`;
  output.push(`function proto_${index}()`);
  output.push(`  source = ${formatLuaString(title)}`);
  output.push(`  stack_slots = ${proto.stack}`);
  output.push(`  parameters = ${proto.params}`);
  for (let i = 0; i < proto.constants.length; i++) output.push(`  constant_${i} = ${formatConstant(proto.constants[i])}`);
  for (let pc = 0; pc < proto.code.length; pc++) {
    const instruction = decodeInstruction(proto.code[pc]);
    const operands = [instruction.A, instruction.B, instruction.C, instruction.k, instruction.Bx, instruction.sBx, instruction.Ax].join(', ');
    output.push(`  instruction_${pc + 1} = ${instruction.name}(${operands})`);
  }
  output.push('end');
  output.push('');
  for (let i = 0; i < proto.children.length; i++) renderProto(proto.children[i], `${index}_${i}`, output);
  return output;
}

function reconstructLuaBytecode(buffer) {
  const reader = new BytecodeReader(buffer);
  const root = reader.proto();
  if (reader.o !== buffer.length) throw new Error('Dados residuais após o bytecode');
  return renderProto(root).join('\n');
}

function createFunctionalLua(buffer, name) {
  const hex = buffer.toString('hex');
  const lines = [
    'local encoded = ' + JSON.stringify(hex),
    'local bytes = {}',
    'for index = 1, #encoded, 2 do',
    '  bytes[#bytes + 1] = string.char(tonumber(encoded:sub(index, index + 1), 16))',
    'end',
    'local payload, loadError = load(table.concat(bytes), ' + JSON.stringify(`@${name}`) + ', "b", _ENV)',
    'if not payload then',
    '  error(loadError)',
    'end',
    'return payload()'
  ];
  return lines.join('\n') + '\n';
}

function luaRegister(index) {
  return Number.isInteger(index) ? `r${index}` : 'nil';
}

function decompiledInstruction(pc, opcode, operands, detail) {
  const values = operands.match(/\d+/g)?.map(Number) || [];
  const a = values[0];
  const b = values[1];
  const c = values[2];
  const constant = detail?.trim();
  const literal = constant?.startsWith('"') && constant.endsWith('"') && constant !== '"' ? constant : null;
  const field = literal?.match(/^"(?:\\.|[^"\\])*"/)?.[0] || 'nil';
  if (opcode === 'MOVE') return `  ${luaRegister(a)} = ${luaRegister(b)}`;
  if (opcode === 'LOADK' && literal) return `  ${luaRegister(a)} = ${literal}`;
  if (opcode === 'LOADI') return `  ${luaRegister(a)} = ${values[1]}`;
  if (opcode === 'LOADFALSE') return `  ${luaRegister(a)} = false`;
  if (opcode === 'LOADTRUE') return `  ${luaRegister(a)} = true`;
  if (opcode === 'LOADNIL') return `  ${luaRegister(a)} = nil`;
  if (opcode === 'NEWTABLE') return `  ${luaRegister(a)} = {}`;
  if (opcode === 'GETFIELD' && constant) return `  ${luaRegister(a)} = ${luaRegister(b)}[${field}]`;
  if (opcode === 'SETFIELD' && constant) return `  ${luaRegister(a)}[${field}] = ${luaRegister(b)}`;
  if (opcode === 'GETI') return `  ${luaRegister(a)} = ${luaRegister(b)}[${c}]`;
  if (opcode === 'SETI') return `  ${luaRegister(a)}[${b}] = ${luaRegister(c)}`;
  if (opcode === 'LEN') return `  ${luaRegister(a)} = #${luaRegister(b)}`;
  if (opcode === 'CONCAT') return `  ${luaRegister(a)} = table.concat({ ${luaRegister(b)}, ${luaRegister(c)} })`;
  if (opcode === 'ADD' || opcode === 'SUB' || opcode === 'MUL' || opcode === 'MOD' || opcode === 'POW' || opcode === 'DIV' || opcode === 'IDIV') {
    const operators = { ADD: '+', SUB: '-', MUL: '*', MOD: '%', POW: '^', DIV: '/', IDIV: '//' };
    return `  ${luaRegister(a)} = ${luaRegister(b)} ${operators[opcode]} ${luaRegister(c)}`;
  }
  if (opcode === 'UNM') return `  ${luaRegister(a)} = -${luaRegister(b)}`;
  if (opcode === 'NOT') return `  ${luaRegister(a)} = not ${luaRegister(b)}`;
  if (opcode === 'JMP') return '  do end';
  if (opcode === 'RETURN0') return '  do return end';
  if (opcode === 'RETURN' || opcode === 'RETURN1') return `  do return ${luaRegister(a)} end`;
  if (opcode === 'CLOSURE') return `  ${luaRegister(a)} = function(...) end`;
  if (opcode === 'CALL') return `  ${luaRegister(a)}(${luaRegister(b)})`;
  if (opcode === 'TAILCALL') return `  do return ${luaRegister(a)}(${luaRegister(b)}) end`;
  if (opcode === 'CLOSE' || opcode === 'TBC' || opcode === 'EXTRAARG') return '  do end';
  return `  do local opcode_${pc} = ${JSON.stringify(opcode)} end`;
}

function decompileLuaBytecode(buffer) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'dazegghost-decompile-'));
  const input = path.join(directory, 'payload.bin');
  fs.writeFileSync(input, buffer);
  try {
    const result = childProcess.spawnSync('luac5.4', ['-l', '-l', input], { encoding: 'utf8' });
    if (result.status !== 0) throw new Error(result.stderr || 'Não foi possível ler o bytecode Lua 5.4');
    const output = ['local decompiled = {}', ''];
    let functionIndex = 0;
    let openFunction = false;
    for (const line of result.stdout.split('\n')) {
      const header = line.match(/^(main|function)\b/);
      if (header) {
        if (openFunction) output.push('end', '');
        output.push(`local function proto_${functionIndex}()`);
        output.push('  local r = {}');
        openFunction = true;
        functionIndex++;
        continue;
      }
      const instruction = line.match(/^\s*(\d+)\s+\[[^\]]*\]\s+([A-Z0-9]+)\s*(.*)$/);
      if (!instruction || !openFunction) continue;
      const detailParts = instruction[3].split(';');
      output.push(decompiledInstruction(Number(instruction[1]), instruction[2], detailParts[0], detailParts[1]));
    }
    if (openFunction) output.push('end', '');
    output.push('return decompiled');
    return output.join('\n');
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
}

function extractArgs(p) {
  const regs = new Array(Math.max(256, p.stack)).fill(null);
  const constants = p.constants;
  let args = null;
  for (let pc = 0; pc < p.code.length; pc++) {
    const ins = p.code[pc];
    const op = ins & 127, A = (ins >>> 7) & 255, k = (ins >>> 15) & 1;
    const B = (ins >>> 16) & 255, C = (ins >>> 24) & 255, Bx = ins >>> 15;
    if (op === 1) regs[A] = Bx - 65535;
    else if (op === 3) regs[A] = constants[Bx];
    else if (op === 5) regs[A] = false;
    else if (op === 7) regs[A] = true;
    else if (op === 8) { for (let j = A; j <= A + B; j++) regs[j] = null; }
    else if (op === 19) regs[A] = [];
    else if (op === 79) regs[A] = { closure: Bx };
    else if (op === 78) {
      let begin = C;
      if (k) {
        const next = p.code[pc + 1];
        if ((next & 127) !== 82) throw new Error('EXTRAARG esperado');
        begin += ((next >>> 7) << 8);
      }
      if (!Array.isArray(regs[A])) throw new Error('SETLIST inesperado');
      for (let j = 0; j < B; j++) regs[A][begin + j] = regs[A + 1 + j];
    } else if (op === 68 || op === 69) {
      if (!regs[A] || regs[A].closure !== 0) throw new Error('CALL de função inesperada');
      args = regs.slice(A + 1, A + B);
    } else if (![6, 70, 81, 82].includes(op)) throw new Error(`Opcode raiz desconhecido: ${op}`);
  }
  if (!args || args.length !== 20) throw new Error('Parâmetros do carregador interno não encontrados');
  return args;
}

function unpackBytecode(b) {
  if (b.subarray(0, 5).toString('latin1') !== '\x1bLuaT') throw new Error('Não é bytecode Lua 5.4');
  const reader = new BytecodeReader(b);
  const root = reader.proto();
  if (reader.o !== b.length) throw new Error('Dados residuais após o bytecode');
  return extractArgs(root);
}

function decode(params, variant) {
  const [P, I, H, A, B, Z, X1, X2, X3, X4, X5, X6, E, Q, V, W, S, N, C, T] = params;
  if (W) throw new Error('Arquivo com senha: este desofuscador é somente para versões sem senha');
  const q1 = (X1 ^ X2) >>> 0, q2 = (X3 ^ X4) >>> 0, q3 = (X5 ^ X6) >>> 0;
  let a = q1, b = q2, c = q3, d = (q1 ^ q2 ^ q3) >>> 0;
  let position = 0, pc = H;
  const result = [];
  const visited = new Set();
  while (true) {
    if (visited.has(pc)) throw new Error('Loop nas instruções da máquina virtual');
    visited.add(pc);
    const ins = I[pc - 1];
    if (!ins) throw new Error(`Instrução inválida: ${pc}`);
    const [op, idx, next] = ins;
    if (op === Z) break;
    if (op === A) {
      const data = P[idx - 1];
      if (!Buffer.isBuffer(data)) throw new Error(`Bloco inválido: ${idx}`);
      for (const input of data) {
        position++;
        let output;
        if (variant === 0) {
          d = (d + a + position + q2) >>> 0;
          c = rotl(c ^ d, 27);
          b = (b + c + q3) >>> 0;
          a = rotl(a ^ b, 11);
          d = (d ^ a ^ c) >>> 0;
          output = input ^ (((a >>> 16) ^ b ^ (c >>> 8) ^ d) & 255);
        } else if (variant === 1) {
          c = (c + a + position + q3) >>> 0;
          d = rotl(d ^ b, 3);
          a = (a + c + q2) >>> 0;
          b = rotl(b ^ d, 15);
          d = (d + a + q3) >>> 0;
          output = input ^ (((a >>> 8) ^ b ^ (c >>> 16) ^ d) & 255);
        } else if (variant === 2) {
          b = (b + a + q2 + position) >>> 0;
          a = rotl(a ^ d, 9);
          d = (d + c + q3 + b) >>> 0;
          c = rotl(c ^ b, 21);
          b = (b ^ c ^ a) >>> 0;
          output = input ^ ((a ^ (b >>> 8) ^ c ^ (d >>> 16)) & 255);
        } else if (variant === 3) {
          a = (a + (b ^ q3) + position) >>> 0;
          c = (c + d + b + q2) >>> 0;
          b = rotl(b ^ c, 5);
          d = rotl(d ^ a, 13);
          a = (a + d + q3) >>> 0;
          c = rotl(c ^ b, 23);
          output = input ^ ((a ^ c ^ (b >>> 8) ^ (d >>> 16)) & 255);
        } else if (variant === 4) {
          a = (a + b + position) >>> 0;
          b = rotl(b ^ a, 7);
          c = (c + d + a) >>> 0;
          d = rotl(d ^ c, 11);
          a = (a + d + q3) >>> 0;
          c = rotl(c ^ b, 17);
          b = (b + c + q2) >>> 0;
          d = rotl(d ^ a, 19);
          output = input ^ ((a ^ b ^ c ^ d) & 255);
        } else throw new Error('Variante inválida');
        result.push(output);
        a = (a ^ (input * 257 + position)) >>> 0;
        d = (d + input + position) >>> 0;
      }
    } else if (op !== B) throw new Error(`Opcode virtual inválido: ${op}`);
    pc = next;
  }
  const buffer = Buffer.from(result);
  const actual = sha256(buffer);
  const expected = Buffer.isBuffer(E) ? E.toString('ascii') : String(E);
  if (actual !== expected) throw new Error(`Hash não confere na variante ${variant + 1}`);
  return buffer;
}

function main() {
  const source = process.argv[2];
  const outputDir = process.argv[3] || path.resolve('camadas_v7');
  if (!source) {
    process.stderr.write('Uso: node desofuscador_v7.js "protegido(7).lua" ./saida\n');
    process.exit(1);
  }
  fs.mkdirSync(outputDir, { recursive: true });
  let parameters = readOuter(fs.readFileSync(source));
  const report = [];
  for (let stage = 1; stage <= 100; stage++) {
    let payload = null, variant = -1;
    for (let mode = 0; mode < 5; mode++) {
      try { payload = decode(parameters, mode); variant = mode + 1; break; }
      catch (e) { if (/com senha|Loop nas|Instrução inválida|Opcode virtual inválido|Bloco inválido/.test(e.message)) throw e; }
    }
    if (!payload) throw new Error(`Nenhuma variante válida na camada ${stage}`);
    const name = `camada_${String(stage).padStart(2, '0')}.bin`;
    fs.writeFileSync(path.join(outputDir, name), payload);
    const item = { camada: stage, variante: variant, bytes: payload.length, sha256: sha256(payload), arquivo: name };
    report.push(item);
    process.stdout.write(`${stage}: variante ${variant}, ${payload.length} bytes, SHA-256 OK\n`);
    try { parameters = unpackBytecode(payload); }
    catch (e) {
      if (e.message !== 'Parâmetros do carregador interno não encontrados' && e.message !== 'Opcode raiz desconhecido: 11') {
        if (!/CALL de função inesperada|Opcode raiz desconhecido|Não é bytecode Lua 5.4/.test(e.message)) process.stderr.write(`Aviso: ${e.message}\n`);
      }
      break;
    }
  }
  const finalFile = path.join(outputDir, report[report.length - 1].arquivo);
  fs.copyFileSync(finalFile, path.join(outputDir, 'payload_final.bin'));
  const analysis = [];
  for (const item of report) {
    const binary = fs.readFileSync(path.join(outputDir, item.arquivo));
    const prefix = path.join(outputDir, item.arquivo.replace(/\.bin$/, ''));
    fs.writeFileSync(`${prefix}.reconstructed.lua`, decompileLuaBytecode(binary));
    fs.writeFileSync(`${prefix}.functional.lua`, createFunctionalLua(binary, item.arquivo));
    analysis.push({ arquivo: item.arquivo, reconstructed: path.basename(`${prefix}.reconstructed.lua`) });
  }
  const finalBinary = fs.readFileSync(finalFile);
  fs.writeFileSync(path.join(outputDir, 'payload_final.reconstructed.lua'), decompileLuaBytecode(finalBinary));
  fs.writeFileSync(path.join(outputDir, 'payload_final.functional.lua'), createFunctionalLua(finalBinary, 'payload_final.bin'));
  fs.writeFileSync(path.join(outputDir, 'relatorio.json'), JSON.stringify(report, null, 2));
  fs.writeFileSync(path.join(outputDir, 'analise.json'), JSON.stringify(analysis, null, 2));
  process.stdout.write(`Finalizado: ${report.length} camadas. Payload: ${path.join(outputDir, 'payload_final.bin')}\n`);
}

if (require.main === module) main();

module.exports = { BytecodeReader, createFunctionalLua, decompileLuaBytecode, unpackBytecode };
