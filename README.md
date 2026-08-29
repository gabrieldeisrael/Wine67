# Wine67 / StartX

**Wine67** (também conhecido como **StartX**) é um script utilitário para Linux que permite rodar jogos e programas `.exe` direto de um pendrive (formatado em ExFAT), **sem precisar de privilégios de sudo/root** no PC host. Basta plugar e jogar.

> ⚠️ **Recomendado: use o `wine67.sh`**
> O projeto conta com mais de uma versão do script, mas o **`wine67.sh` é o mais estável** e o recomendado para uso no dia a dia. Prefira sempre essa versão ao rodar o projeto.

## ✨ Funcionalidades

- Roda executáveis `.exe` via **WineWOW64**
- Não requer instalação nem permissões administrativas no computador host
- Detecta automaticamente os arquivos `.exe` disponíveis no pendrive
- Menu simples de seleção por número

## 📋 Pré-requisitos

- Pendrive formatado em **ExFAT**
- Linux com WineWOW64 já disponível no sistema
- Permissão de execução para o script (veja abaixo)

## 🚀 Como usar

1. **Acesse o diretório**
   Abra o terminal na pasta onde os arquivos do StartX/Wine67 estão localizados.

2. **Dê permissão de execução**
   ```bash
   chmod +x wine67.sh
   ```

3. **Inicie o script**
   ```bash
   ./wine67.sh
   ```

4. **Selecione o programa**
   O script lista todos os arquivos `.exe` encontrados. Digite o número correspondente ao programa desejado e pressione Enter. A execução é feita via **WineWOW64**.

5. **Feche normalmente**
   Após o uso, basta fechar o programa como de costume.

*(Obs: se escolher StartX, apenas troque o `.sh` nos comandos por `startx.sh`)*

> 💡 **Dica:** se o Wine solicitar a instalação do **Wine Mono** ou **Wine Gecko** durante a execução, sempre aceite e instale — isso evita erros e melhora a compatibilidade com diversos programas.
