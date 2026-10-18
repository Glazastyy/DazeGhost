local Programa = {}

Programa.configuracao = {
    mensagem = "Olá, mundo!",
    ativo = true,
    repeticoes = 1
}

Programa.estado = {
    inicializado = false,
    executado = false,
    resultado = nil
}

function Programa:inicializar()
    self.estado.inicializado = true
end

function Programa:obterMensagem()
    local palavras = {}

    for palavra in self.configuracao.mensagem:gmatch("%S+") do
        table.insert(palavras, palavra)
    end

    return table.concat(palavras, " ")
end

function Programa:processarMensagem(mensagem)
    local caracteres = {}

    for i = 1, #mensagem do
        caracteres[#caracteres + 1] = mensagem:sub(i, i)
    end

    return table.concat(caracteres)
end

function Programa:executar()
    if not self.estado.inicializado then
        self:inicializar()
    end

    if not self.configuracao.ativo then
        return false
    end

    local mensagem = self:obterMensagem()
    local resultado = self:processarMensagem(mensagem)

    for i = 1, self.configuracao.repeticoes do
        print(resultado)
    end

    self.estado.resultado = resultado
    self.estado.executado = true

    return true
end

local function principal()
    local sucesso, erro = pcall(function()
        Programa:executar()
    end)

    if not sucesso then
        io.stderr:write(tostring(erro) .. "\n")
    end
end

principal()