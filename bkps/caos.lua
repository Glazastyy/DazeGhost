local Config = {
    raiz = "lua_laboratorio_aleatorio",
    quantidadeArquivos = 45,
    quantidadeRodadas = 12,
    quantidadeWorkers = 8,
    linhasPorArquivo = 15,
    quantidadeNumeros = 600,
    verboso = true,
    nomeProjeto = "Laboratorio de Operacoes Absolutamente Desnecessarias"
}

math.randomseed(os.time())

local Sistema = {
    inicio = os.clock(),
    eventos = {},
    arquivos = {},
    tarefas = {},
    metricas = {
        arquivosCriados = 0,
        leituras = 0,
        escritas = 0,
        operacoesMatematicas = 0,
        transformacoes = 0,
        tarefasExecutadas = 0,
        checkpoints = 0,
        erros = 0,
        bytesEscritos = 0
    }
}

local function separador()
    return package.config:sub(1, 1)
end

local SEP = separador()

local function caminho(...)
    return table.concat({...}, SEP)
end

local function criarDiretorio(diretorio)
    local comando

    if SEP == "\\" then
        comando = 'mkdir "' .. diretorio .. '" >NUL 2>NUL'
    else
        comando = 'mkdir -p "' .. diretorio .. '"'
    end

    local resultado = os.execute(comando)

    return resultado == true or resultado == 0
end

local function existeArquivo(nome)
    local arquivo = io.open(nome, "rb")

    if arquivo then
        arquivo:close()
        return true
    end

    return false
end

local function gerarIdentificador(tamanho)
    local caracteres = "abcdefghijklmnopqrstuvwxyz0123456789"
    local resultado = {}

    for i = 1, tamanho do
        local indice = math.random(1, #caracteres)
        resultado[i] = caracteres:sub(indice, indice)
    end

    return table.concat(resultado)
end

local function dataAtual()
    return os.date("%Y-%m-%d %H:%M:%S")
end

local function registrar(tipo, mensagem)
    local evento = {
        tipo = tipo,
        mensagem = tostring(mensagem),
        data = dataAtual(),
        instante = os.clock()
    }

    Sistema.eventos[#Sistema.eventos + 1] = evento

    if Config.verboso then
        print("[" .. tipo .. "] " .. evento.mensagem)
    end
end

local function garantirDiretorio(diretorio)
    if not criarDiretorio(diretorio) then
        error("Falha ao preparar diretorio: " .. diretorio)
    end
end

garantirDiretorio(Config.raiz)

local pastaExecucao

for tentativa = 1, 100 do
    local identificador = os.date("%Y%m%d_%H%M%S")
        .. "_"
        .. gerarIdentificador(12)

    local candidato = caminho(
        Config.raiz,
        "execucao_" .. identificador
    )

    if not existeArquivo(candidato) then
        pastaExecucao = candidato
        break
    end
end

if not pastaExecucao then
    error("Nao foi possivel gerar uma pasta unica")
end

garantirDiretorio(pastaExecucao)

local Diretorios = {
    dados = caminho(pastaExecucao, "dados"),
    logs = caminho(pastaExecucao, "logs"),
    relatorios = caminho(pastaExecucao, "relatorios"),
    temporarios = caminho(pastaExecucao, "temporarios"),
    checkpoints = caminho(pastaExecucao, "checkpoints"),
    resultados = caminho(pastaExecucao, "resultados")
}

for _, diretorio in pairs(Diretorios) do
    garantirDiretorio(diretorio)
end

local function escrever(nome, conteudo, modo)
    local arquivo, erro = io.open(nome, modo or "ab")

    if not arquivo then
        Sistema.metricas.erros = Sistema.metricas.erros + 1
        registrar("ERRO", erro or "Falha desconhecida")
        return false
    end

    local texto = tostring(conteudo)

    local ok, erroEscrita = arquivo:write(texto)

    if not ok then
        Sistema.metricas.erros = Sistema.metricas.erros + 1
        arquivo:close()
        registrar("ERRO", erroEscrita or "Falha na escrita")
        return false
    end

    arquivo:close()

    Sistema.metricas.escritas = Sistema.metricas.escritas + 1
    Sistema.metricas.bytesEscritos =
        Sistema.metricas.bytesEscritos + #texto

    return true
end

local function ler(nome)
    local arquivo = io.open(nome, "rb")

    if not arquivo then
        return nil
    end

    local conteudo = arquivo:read("*a")
    arquivo:close()

    Sistema.metricas.leituras = Sistema.metricas.leituras + 1

    return conteudo
end

local function criarArquivo(nome, conteudo)
    if existeArquivo(nome) then
        return false
    end

    if escrever(nome, conteudo or "", "wb") then
        Sistema.metricas.arquivosCriados =
            Sistema.metricas.arquivosCriados + 1

        Sistema.arquivos[#Sistema.arquivos + 1] = nome

        return true
    end

    return false
end

local function escolher(tabela)
    return tabela[math.random(1, #tabela)]
end

local palavras = {
    "banana",
    "algoritmo",
    "universo",
    "paralelepipedo",
    "computador",
    "abacaxi",
    "galaxia",
    "processador",
    "cafe",
    "matematica",
    "aleatoriedade",
    "desnecessario",
    "hipopotamo",
    "ornitorrinco",
    "meteorito",
    "infinito",
    "lua",
    "computacao",
    "estrutura",
    "simulacao",
    "laboratorio",
    "experimento",
    "variavel",
    "funcao",
    "misterio",
    "pipoca",
    "tartaruga",
    "criptografia",
    "nebulosa",
    "eletricidade",
    "teclado",
    "memoria",
    "virtualizacao",
    "internet",
    "programacao",
    "redundancia",
    "sincronizacao",
    "aleatorio",
    "estatistica",
    "biblioteca"
}

local function gerarFrase()
    local quantidade = math.random(5, 14)
    local frase = {}

    for i = 1, quantidade do
        frase[i] = escolher(palavras)
    end

    return table.concat(frase, " ") .. "."
end

local function gerarTexto(linhas)
    local resultado = {}

    for i = 1, linhas do
        resultado[i] = string.format(
            "[%04d] %s",
            i,
            gerarFrase()
        )
    end

    return table.concat(resultado, "\n") .. "\n"
end

local function inverterTexto(texto)
    Sistema.metricas.transformacoes =
        Sistema.metricas.transformacoes + 1

    return texto:reverse()
end

local function alternarMaiusculas(texto)
    local resultado = {}

    for i = 1, #texto do
        local caractere = texto:sub(i, i)

        if i % 2 == 0 then
            resultado[i] = caractere:upper()
        else
            resultado[i] = caractere:lower()
        end
    end

    Sistema.metricas.transformacoes =
        Sistema.metricas.transformacoes + 1

    return table.concat(resultado)
end

local function contarPalavras(texto)
    local quantidade = 0

    for _ in texto:gmatch("%S+") do
        quantidade = quantidade + 1
    end

    return quantidade
end

local function gerarNumeros(quantidade)
    local numeros = {}

    for i = 1, quantidade do
        numeros[i] = math.random(-10000, 10000)
    end

    return numeros
end

local function calcularEstatisticas(numeros)
    local soma = 0
    local minimo = math.huge
    local maximo = -math.huge

    for _, numero in ipairs(numeros) do
        soma = soma + numero

        if numero < minimo then
            minimo = numero
        end

        if numero > maximo then
            maximo = numero
        end

        Sistema.metricas.operacoesMatematicas =
            Sistema.metricas.operacoesMatematicas + 1
    end

    local quantidade = #numeros

    if quantidade == 0 then
        return {
            soma = 0,
            media = 0,
            minimo = 0,
            maximo = 0,
            mediana = 0,
            variancia = 0
        }
    end

    local media = soma / quantidade
    local variancia = 0

    for _, numero in ipairs(numeros) do
        variancia = variancia + (numero - media) ^ 2
    end

    variancia = variancia / quantidade

    local ordenados = {}

    for i, numero in ipairs(numeros) do
        ordenados[i] = numero
    end

    table.sort(ordenados)

    local mediana

    if quantidade % 2 == 0 then
        mediana = (
            ordenados[quantidade / 2] +
            ordenados[quantidade / 2 + 1]
        ) / 2
    else
        mediana = ordenados[math.floor(quantidade / 2) + 1]
    end

    return {
        soma = soma,
        media = media,
        minimo = minimo,
        maximo = maximo,
        mediana = mediana,
        variancia = variancia
    }
end

local function fibonacci(n)
    local a, b = 0, 1

    for _ = 1, n do
        a, b = b, a + b

        Sistema.metricas.operacoesMatematicas =
            Sistema.metricas.operacoesMatematicas + 1
    end

    return a
end

local function fatorial(n)
    local resultado = 1

    for i = 2, n do
        resultado = resultado * i

        Sistema.metricas.operacoesMatematicas =
            Sistema.metricas.operacoesMatematicas + 1
    end

    return resultado
end

local function ehPrimo(numero)
    if numero < 2 then
        return false
    end

    for i = 2, math.floor(math.sqrt(numero)) do
        if numero % i == 0 then
            return false
        end
    end

    return true
end

local function gerarPrimos(limite)
    local primos = {}

    for numero = 2, limite do
        if ehPrimo(numero) then
            primos[#primos + 1] = numero
        end

        Sistema.metricas.operacoesMatematicas =
            Sistema.metricas.operacoesMatematicas + 1
    end

    return primos
end

local function embaralhar(tabela)
    for i = #tabela, 2, -1 do
        local j = math.random(1, i)

        tabela[i], tabela[j] = tabela[j], tabela[i]
    end

    return tabela
end

local function serializarJSON(valor)
    local tipo = type(valor)

    if tipo == "nil" then
        return "null"
    end

    if tipo == "boolean" then
        return tostring(valor)
    end

    if tipo == "number" then
        if valor ~= valor
            or valor == math.huge
            or valor == -math.huge then
            return "null"
        end

        return tostring(valor)
    end

    if tipo == "string" then
        local resultado = valor:gsub('[%z\1-\31\\"]', function(c)
            local especiais = {
                ['"'] = '\\"',
                ["\\"] = "\\\\",
                ["\n"] = "\\n",
                ["\r"] = "\\r",
                ["\t"] = "\\t",
                ["\b"] = "\\b",
                ["\f"] = "\\f"
            }

            return especiais[c] or string.format(
                "\\u%04x",
                c:byte()
            )
        end)

        return '"' .. resultado .. '"'
    end

    if tipo == "table" then
        local ehArray = true
        local quantidade = 0
        local maiorIndice = 0

        for chave in pairs(valor) do
            quantidade = quantidade + 1

            if type(chave) ~= "number"
                or chave < 1
                or chave % 1 ~= 0 then
                ehArray = false
            else
                maiorIndice = math.max(maiorIndice, chave)
            end
        end

        if ehArray and maiorIndice == quantidade then
            local partes = {}

            for i = 1, quantidade do
                partes[#partes + 1] = serializarJSON(valor[i])
            end

            return "[" .. table.concat(partes, ",") .. "]"
        end

        local partes = {}

        for chave, item in pairs(valor) do
            partes[#partes + 1] =
                serializarJSON(tostring(chave))
                .. ":"
                .. serializarJSON(item)
        end

        table.sort(partes)

        return "{" .. table.concat(partes, ",") .. "}"
    end

    return "null"
end

local function salvarJSON(nome, dados)
    return escrever(nome, serializarJSON(dados), "wb")
end

local function criarCheckpoint(nome, dados)
    local arquivo = caminho(
        Diretorios.checkpoints,
        nome .. "_" .. gerarIdentificador(8) .. ".json"
    )

    local sucesso = salvarJSON(arquivo, {
        identificador = gerarIdentificador(16),
        criadoEm = dataAtual(),
        dados = dados,
        metricas = Sistema.metricas
    })

    if sucesso then
        Sistema.metricas.checkpoints =
            Sistema.metricas.checkpoints + 1
    end

    return sucesso
end

local function tarefaCriacaoArquivos(worker)
    registrar("WORKER", "Criador de arquivos iniciado: " .. worker)

    for i = 1, Config.quantidadeArquivos do
        local nome = string.format(
            "arquivo_%03d_%s.txt",
            i,
            gerarIdentificador(8)
        )

        local arquivo = caminho(Diretorios.dados, nome)

        criarArquivo(
            arquivo,
            gerarTexto(Config.linhasPorArquivo)
        )

        if i % 5 == 0 then
            registrar("ARQUIVO", "Lote criado: " .. i)
            coroutine.yield()
        end
    end

    registrar("WORKER", "Criacao finalizada")
end

local function tarefaMatematica(worker)
    registrar("WORKER", "Matematica iniciada: " .. worker)

    for rodada = 1, Config.quantidadeRodadas do
        local numeros = gerarNumeros(Config.quantidadeNumeros)
        local estatisticas = calcularEstatisticas(numeros)

        local resultado = {
            rodada = rodada,
            worker = worker,
            estatisticas = estatisticas,
            fibonacci = fibonacci(math.random(10, 50)),
            fatorial = fatorial(math.random(3, 15)),
            quantidadeNumeros = #numeros
        }

        salvarJSON(
            caminho(
                Diretorios.resultados,
                "matematica_" .. rodada .. ".json"
            ),
            resultado
        )

        registrar(
            "MATH",
            string.format(
                "Rodada %d, media %.2f, mediana %.2f",
                rodada,
                estatisticas.media,
                estatisticas.mediana
            )
        )

        coroutine.yield()
    end
end

local function tarefaPrimos(worker)
    registrar("WORKER", "Busca de primos iniciada: " .. worker)

    for rodada = 1, Config.quantidadeRodadas do
        local limite = math.random(100, 2000)
        local primos = gerarPrimos(limite)

        salvarJSON(
            caminho(
                Diretorios.resultados,
                "primos_" .. rodada .. ".json"
            ),
            {
                rodada = rodada,
                limite = limite,
                quantidade = #primos,
                valores = primos
            }
        )

        registrar(
            "PRIMOS",
            "Encontrados " .. #primos .. " primos"
        )

        coroutine.yield()
    end
end

local function tarefaStrings(worker)
    registrar("WORKER", "Strings iniciadas: " .. worker)

    for rodada = 1, Config.quantidadeRodadas do
        local texto = gerarTexto(math.random(5, 20))

        local resultado = {
            original = texto,
            invertido = inverterTexto(texto),
            alternado = alternarMaiusculas(texto),
            maiusculo = texto:upper(),
            minusculo = texto:lower(),
            palavras = contarPalavras(texto),
            caracteres = #texto,
            rodada = rodada
        }

        salvarJSON(
            caminho(
                Diretorios.resultados,
                "strings_" .. rodada .. ".json"
            ),
            resultado
        )

        registrar(
            "STRING",
            "Transformadas " .. resultado.palavras .. " palavras"
        )

        coroutine.yield()
    end
end

local function tarefaModificacao(worker)
    registrar("WORKER", "Modificador iniciado: " .. worker)

    for rodada = 1, Config.quantidadeRodadas do
        local quantidade = #Sistema.arquivos

        if quantidade == 0 then
            registrar("MOD", "Nenhum arquivo disponivel")
        else
            for i = 1, math.min(10, quantidade) do
                local arquivo = escolher(Sistema.arquivos)

                local conteudo = string.format(
                    "\n[ALTERACAO] worker=%s rodada=%d token=%s\n%s\n",
                    worker,
                    rodada,
                    gerarIdentificador(16),
                    gerarFrase()
                )

                escrever(arquivo, conteudo, "ab")
            end
        end

        registrar(
            "MOD",
            "Rodada de modificacoes " .. rodada
        )

        coroutine.yield()
    end
end

local function tarefaLeitura(worker)
    registrar("WORKER", "Leitor iniciado: " .. worker)

    for rodada = 1, Config.quantidadeRodadas do
        local analise = {}

        for i = 1, math.min(10, #Sistema.arquivos) do
            local arquivo = Sistema.arquivos[i]
            local conteudo = ler(arquivo)

            if conteudo then
                analise[#analise + 1] = {
                    arquivo = arquivo,
                    caracteres = #conteudo,
                    palavras = contarPalavras(conteudo),
                    linhas = select(
                        2,
                        conteudo:gsub("\n", "")
                    )
                }
            end
        end

        salvarJSON(
            caminho(
                Diretorios.relatorios,
                "analise_" .. rodada .. ".json"
            ),
            analise
        )

        registrar("LEITURA", "Analise " .. rodada .. " concluida")

        coroutine.yield()
    end
end

local function tarefaAleatoria(worker)
    registrar("WORKER", "Aleatoriedade iniciada: " .. worker)

    local operacoes = {
        function()
            return fibonacci(math.random(5, 30))
        end,

        function()
            return fatorial(math.random(2, 12))
        end,

        function()
            return gerarIdentificador(math.random(5, 40))
        end,

        function()
            return inverterTexto(gerarFrase())
        end,

        function()
            return alternarMaiusculas(gerarFrase())
        end,

        function()
            return #gerarPrimos(math.random(50, 500))
        end,

        function()
            local numeros = gerarNumeros(30)
            embaralhar(numeros)
            return table.concat(numeros, ",")
        end,

        function()
            return contarPalavras(gerarTexto(10))
        end,

        function()
            return math.sqrt(math.random(1, 100000))
        end,

        function()
            return math.sin(math.random() * math.pi)
        end
    }

    for rodada = 1, Config.quantidadeRodadas * 3 do
        local indice = math.random(1, #operacoes)
        local resultado = operacoes[indice]()

        escrever(
            caminho(
                Diretorios.logs,
                "operacoes_aleatorias.log"
            ),
            string.format(
                "[%s] operacao=%d resultado=%s\n",
                dataAtual(),
                indice,
                tostring(resultado)
            ),
            "ab"
        )

        registrar(
            "RANDOM",
            "Operacao " .. indice .. " executada"
        )

        coroutine.yield()
    end
end

local function tarefaCheckpoints(worker)
    registrar("WORKER", "Checkpoints iniciados: " .. worker)

    for rodada = 1, Config.quantidadeRodadas do
        criarCheckpoint(
            "checkpoint_" .. rodada,
            {
                worker = worker,
                rodada = rodada,
                token = gerarIdentificador(24),
                mensagem = gerarFrase(),
                arquivosConhecidos = #Sistema.arquivos
            }
        )

        registrar(
            "CHECKPOINT",
            "Checkpoint " .. rodada .. " registrado"
        )

        coroutine.yield()
    end
end

local function tarefaMatrizes(worker)
    registrar("WORKER", "Matrizes iniciadas: " .. worker)

    local function criarMatriz(tamanho)
        local matriz = {}

        for i = 1, tamanho do
            matriz[i] = {}

            for j = 1, tamanho do
                matriz[i][j] = math.random(-50, 50)
            end
        end

        return matriz
    end

    local function multiplicarMatrizes(a, b)
        local tamanho = #a
        local resultado = {}

        for i = 1, tamanho do
            resultado[i] = {}

            for j = 1, tamanho do
                local soma = 0

                for k = 1, tamanho do
                    soma = soma + a[i][k] * b[k][j]

                    Sistema.metricas.operacoesMatematicas =
                        Sistema.metricas.operacoesMatematicas + 1
                end

                resultado[i][j] = soma
            end
        end

        return resultado
    end

    for rodada = 1, Config.quantidadeRodadas do
        local tamanho = math.random(2, 8)
        local matrizA = criarMatriz(tamanho)
        local matrizB = criarMatriz(tamanho)

        local resultado = multiplicarMatrizes(matrizA, matrizB)

        salvarJSON(
            caminho(
                Diretorios.resultados,
                "matriz_" .. rodada .. ".json"
            ),
            {
                rodada = rodada,
                tamanho = tamanho,
                matrizA = matrizA,
                matrizB = matrizB,
                resultado = resultado
            }
        )

        registrar(
            "MATRIZ",
            "Multiplicacao " .. tamanho .. "x" .. tamanho
        )

        coroutine.yield()
    end
end

local function tarefaOrdenacao(worker)
    registrar("WORKER", "Ordenacao iniciada: " .. worker)

    for rodada = 1, Config.quantidadeRodadas do
        local numeros = gerarNumeros(math.random(50, 300))
        local original = {}

        for i, numero in ipairs(numeros) do
            original[i] = numero
        end

        table.sort(numeros)

        local crescente = {}

        for i, numero in ipairs(numeros) do
            crescente[i] = numero
        end

        table.sort(numeros, function(a, b)
            return a > b
        end)

        salvarJSON(
            caminho(
                Diretorios.resultados,
                "ordenacao_" .. rodada .. ".json"
            ),
            {
                rodada = rodada,
                original = original,
                crescente = crescente,
                decrescente = numeros
            }
        )

        registrar(
            "SORT",
            "Ordenados " .. #numeros .. " numeros"
        )

        coroutine.yield()
    end
end

local function tarefaExperimentos(worker)
    registrar("WORKER", "Experimentos iniciados: " .. worker)

    for rodada = 1, Config.quantidadeRodadas do
        local experimento = {
            identificador = gerarIdentificador(20),
            instante = dataAtual(),
            worker = worker,
            rodada = rodada,
            resultados = {}
        }

        for i = 1, 20 do
            local a = math.random(1, 1000)
            local b = math.random(1, 1000)

            experimento.resultados[#experimento.resultados + 1] = {
                a = a,
                b = b,
                soma = a + b,
                produto = a * b,
                diferenca = a - b,
                divisao = a / b,
                modulo = a % b,
                potencia = a ^ 2,
                raiz = math.sqrt(a)
            }

            Sistema.metricas.operacoesMatematicas =
                Sistema.metricas.operacoesMatematicas + 9
        end

        salvarJSON(
            caminho(
                Diretorios.resultados,
                "experimento_" .. rodada .. ".json"
            ),
            experimento
        )

        registrar(
            "EXPERIMENTO",
            "Experimento " .. rodada .. " concluido"
        )

        coroutine.yield()
    end
end

local function tarefaLogs(worker)
    registrar("WORKER", "Gerador de logs iniciado: " .. worker)

    local niveis = {
        "INFO",
        "DEBUG",
        "TRACE",
        "NOTICE",
        "SIMULACAO",
        "DIAGNOSTICO"
    }

    for rodada = 1, Config.quantidadeRodadas * 4 do
        local nivel = escolher(niveis)

        local mensagem = string.format(
            "[%s] [%s] worker=%s rodada=%d id=%s mensagem=%s\n",
            dataAtual(),
            nivel,
            worker,
            rodada,
            gerarIdentificador(10),
            gerarFrase()
        )

        escrever(
            caminho(Diretorios.logs, "eventos_ficticios.log"),
            mensagem,
            "ab"
        )

        if rodada % 4 == 0 then
            registrar(
                "LOG",
                "Gerados " .. rodada .. " eventos ficticios"
            )

            coroutine.yield()
        end
    end
end

local function registrarTarefa(nome, funcao)
    local identificador = #Sistema.tarefas + 1

    Sistema.tarefas[#Sistema.tarefas + 1] = {
        nome = nome,
        identificador = identificador,
        corrotina = coroutine.create(function()
            funcao("worker_" .. identificador)
        end),
        finalizada = false,
        execucoes = 0
    }
end

local function executarScheduler()
    registrar("SCHEDULER", "Iniciando agendador cooperativo")

    local ciclo = 0

    while true do
        local pendentes = 0

        ciclo = ciclo + 1

        for _, tarefa in ipairs(Sistema.tarefas) do
            if not tarefa.finalizada then
                pendentes = pendentes + 1

                local sucesso, erro = coroutine.resume(
                    tarefa.corrotina
                )

                tarefa.execucoes = tarefa.execucoes + 1

                Sistema.metricas.tarefasExecutadas =
                    Sistema.metricas.tarefasExecutadas + 1

                if not sucesso then
                    Sistema.metricas.erros =
                        Sistema.metricas.erros + 1

                    registrar(
                        "ERRO",
                        tarefa.nome .. ": " .. tostring(erro)
                    )

                    tarefa.finalizada = true
                elseif coroutine.status(tarefa.corrotina) == "dead" then
                    tarefa.finalizada = true

                    registrar(
                        "FINALIZADA",
                        tarefa.nome
                    )
                end
            end
        end

        if pendentes == 0 then
            break
        end

        if ciclo % 10 == 0 then
            registrar(
                "SCHEDULER",
                "Ciclo " .. ciclo .. " concluido"
            )
        end
    end

    registrar(
        "SCHEDULER",
        "Todas as tarefas foram processadas"
    )
end

local function gerarRelatorioFinal()
    local duracao = os.clock() - Sistema.inicio

    local tarefas = {}

    for _, tarefa in ipairs(Sistema.tarefas) do
        tarefas[#tarefas + 1] = {
            nome = tarefa.nome,
            identificador = tarefa.identificador,
            finalizada = tarefa.finalizada,
            execucoes = tarefa.execucoes
        }
    end

    local relatorio = {
        projeto = Config.nomeProjeto,
        concluidoEm = dataAtual(),
        duracaoCPU = duracao,
        pastaExecucao = pastaExecucao,
        configuracao = Config,
        metricas = Sistema.metricas,
        tarefas = tarefas,
        totalEventos = #Sistema.eventos,
        totalArquivosMonitorados = #Sistema.arquivos
    }

    salvarJSON(
        caminho(
            Diretorios.relatorios,
            "relatorio_final.json"
        ),
        relatorio
    )

    local texto = {
        "==============================================",
        "RELATORIO ABSOLUTAMENTE DESNECESSARIO",
        "==============================================",
        "",
        "Projeto: " .. Config.nomeProjeto,
        "Data: " .. dataAtual(),
        "Pasta: " .. pastaExecucao,
        "",
        "Arquivos criados: " .. Sistema.metricas.arquivosCriados,
        "Leituras: " .. Sistema.metricas.leituras,
        "Escritas: " .. Sistema.metricas.escritas,
        "Bytes escritos: " .. Sistema.metricas.bytesEscritos,
        "Operacoes matematicas: " .. Sistema.metricas.operacoesMatematicas,
        "Transformacoes: " .. Sistema.metricas.transformacoes,
        "Execucoes de tarefas: " .. Sistema.metricas.tarefasExecutadas,
        "Checkpoints: " .. Sistema.metricas.checkpoints,
        "Erros: " .. Sistema.metricas.erros,
        "Eventos: " .. #Sistema.eventos,
        "Tempo de CPU: " .. string.format("%.4f", duracao),
        "",
        "Conclusao:",
        "Uma quantidade desnecessaria de trabalho foi realizada.",
        "Diversos arquivos agora contem informacoes ficticias.",
        "Nenhuma dessas informacoes possui utilidade pratica.",
        "",
        "=============================================="
    }

    escrever(
        caminho(
            Diretorios.relatorios,
            "relatorio_final.txt"
        ),
        table.concat(texto, "\n") .. "\n",
        "wb"
    )

    print("")
    print(table.concat(texto, "\n"))
end

local function salvarHistorico()
    local eventos = {}

    for i, evento in ipairs(Sistema.eventos) do
        eventos[i] = {
            tipo = evento.tipo,
            mensagem = evento.mensagem,
            data = evento.data,
            instante = evento.instante
        }
    end

    salvarJSON(
        caminho(Diretorios.logs, "historico_completo.json"),
        eventos
    )
end

local function executar()
    print("")
    print("==============================================")
    print("LABORATORIO DE OPERACOES DESNECESSARIAS")
    print("==============================================")
    print("")

    registrar("SISTEMA", "Inicializando ambiente")

    registrarTarefa("Criacao de arquivos", tarefaCriacaoArquivos)
    registrarTarefa("Calculos matematicos", tarefaMatematica)
    registrarTarefa("Numeros primos", tarefaPrimos)
    registrarTarefa("Transformacoes de strings", tarefaStrings)
    registrarTarefa("Modificacao de arquivos", tarefaModificacao)
    registrarTarefa("Leitura de arquivos", tarefaLeitura)
    registrarTarefa("Operacoes aleatorias", tarefaAleatoria)
    registrarTarefa("Checkpoints", tarefaCheckpoints)
    registrarTarefa("Multiplicacao de matrizes", tarefaMatrizes)
    registrarTarefa("Ordenacao de numeros", tarefaOrdenacao)
    registrarTarefa("Experimentos matematicos", tarefaExperimentos)
    registrarTarefa("Geracao de logs", tarefaLogs)

    registrar(
        "SISTEMA",
        "Registradas " .. #Sistema.tarefas .. " tarefas"
    )

    criarCheckpoint("inicial", {
        estado = "inicializado",
        projeto = Config.nomeProjeto
    })

    executarScheduler()

    criarCheckpoint("final", {
        estado = "concluido",
        tarefas = #Sistema.tarefas
    })

    registrar("SISTEMA", "Processamento encerrado")

    salvarHistorico()
    gerarRelatorioFinal()
end

local sucesso, erro = pcall(executar)

if not sucesso then
    io.stderr:write(
        "[FALHA FATAL] " .. tostring(erro) .. "\n"
    )

    os.exit(1)
end