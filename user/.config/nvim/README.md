# 🧠 Neovim — LazyVim setup do Kevin

Configuração **[LazyVim](https://www.lazyvim.org/)** versionada neste dotfiles e implantada via **GNU Stow** (`stow user`). Os arquivos abaixo viram symlinks dentro de `~/.config/nvim/`, então editar aqui = editar a config viva, e vice-versa.

> Stack-alvo: web dev vanilla (HTML/CSS/JS) + TypeScript/React + Laravel/PHP, sobre Omarchy (Arch).

---

## 📦 Pré-requisitos (instalar ANTES de abrir o nvim)

O LazyVim baixa plugins e, via **Mason**, os LSPs/formatters/linters automaticamente no primeiro start. Mas o Mason só consegue instalar/rodar a maioria deles se os **runtimes base** já existirem na máquina:

| Runtime / ferramenta | Por quê | Pacote (Arch) |
|----------------------|---------|---------------|
| **Neovim ≥ 0.10** | base | `neovim` |
| **git** | bootstrap do lazy.nvim e clones | `git` |
| **C compiler** (`gcc`/`clang`) + `make` | compilar parsers do Treesitter | `base-devel` |
| **ripgrep**, **fd** | busca (Telescope/grep) | `ripgrep` `fd` |
| **Node.js + npm** | prettier, live-server, vtsls, emmet, html/css LSP | `nodejs` `npm` (você usa via `mise`) |
| **PHP + Composer** | intelephense, pint, laravel.nvim | `php` `composer` |
| **Python** | pyright/ruff (extra python) | `python` |
| **JDK** | jdtls (extra java/kotlin) | `jdk-openjdk` |

Sem o runtime correspondente, a feature daquela linguagem simplesmente não ativa — o resto do editor funciona normalmente.

---

## 🚀 Implantação numa workstation nova

```bash
git clone git@github.com:kevinbsr/dotfiles.git ~/dotfiles
cd ~/dotfiles
stow --restow --target="$HOME" user                # ou: sudo ./install.sh
nvim                                                # 1º start: lazy + Mason instalam tudo
```

No **primeiro start** o LazyVim: clona o `lazy.nvim`, instala todos os plugins, compila os parsers do Treesitter e dispara o Mason para baixar LSPs/formatters. O CLI `live-server` é instalado sozinho pelo `build` do plugin (`npm install -g live-server`). Pode levar alguns minutos; rode `:Lazy` e `:Mason` para acompanhar / `:checkhealth` para diagnosticar.

---

## ✅ Suporte out-of-the-box por linguagem

| Linguagem | LSP | Formatter | Highlight | Extras |
|-----------|-----|-----------|-----------|--------|
| **HTML** | `html` (vscode-html) | prettier | ✓ | auto-close/rename de tags, Emmet inline |
| **CSS** | `cssls` (vscode-css) | prettier | ✓ | validação + preview de cor |
| **JS/JSX** | `vtsls` | prettier | ✓ | Emmet em JSX |
| **TS/TSX** | `vtsls` | prettier | ✓ | extra `lang.typescript` |
| **Tailwind** | `tailwindcss` | — | — | extra `lang.tailwind` |
| **PHP** | `intelephense` (PHP 8.5) | `pint` | ✓ | laravel.nvim |
| **Blade** | `intelephense` | `blade-formatter` | ✓ (parser externo) | filetype `*.blade.php` |
| **JSON** | `jsonls` + schemastore | prettier | ✓ | extra `lang.json` |
| **Markdown** | `marksman` | — | ✓ | lint `markdownlint-cli2` (config global `~/.markdownlint.yaml`) |
| **Python** | `pyright` / `ruff` | — | ✓ | extra `lang.python` |
| **Java / Kotlin** | `jdtls` / `kotlin-ls` | — | ✓ | extras |
| **Docker / Terraform / YAML / Git** | ✓ | — | ✓ | extras correspondentes |

**LazyVim extras habilitados** (`lazyvim.json`): `editor.neo-tree`, `lang.docker`, `lang.git`, `lang.java`, `lang.json`, `lang.kotlin`, `lang.markdown`, `lang.php`, `lang.python`, `lang.tailwind`, `lang.terraform`, `lang.typescript`, `lang.yaml`.

---

## ⌨️ Keymaps customizados (além dos padrões do LazyVim)

| Tecla | Modo | Ação |
|-------|------|------|
| `jj` | insert | `<ESC>` |
| `<leader>xe` | normal | Emmet: envolver seleção com abreviação |
| `<leader>xl` | normal | Live Server: iniciar (auto-reload no save) |
| `<leader>xL` | normal | Live Server: parar |
| `<leader>p…` | normal | Grupo Laravel (artisan, rotas, make, view finder, etc.) |
| `<leader>co` / `<leader>cR` | normal | TS: organizar imports / renomear arquivo |

Front-end usa **2 espaços** (autocmd em `lua/config/autocmds.lua` para js/ts/css/html/json). `relativenumber` desligado.

---

## 🗂️ O que tem aqui

```
lua/config/        # overrides base do LazyVim (lazy, options, keymaps, autocmds)
lua/plugins/
├── frontend.lua              # HTML/CSS/JS: autotag, emmet, prettier, LSPs html/cssls/emmet
├── live-server.lua           # servidor local + live reload (equivalente ao Live Server do VSCode)
├── laravel.lua               # PHP/Blade: intelephense, pint, blade-formatter, laravel.nvim
├── markdown-override.lua     # markdownlint global
├── all-themes.lua            # catálogo de colorschemes (lazy) p/ hot-reload do tema
├── omarchy-theme-hotreload.lua # recarrega o tema quando o Omarchy troca de tema
├── disable-news-alert.lua    # silencia avisos de news do LazyVim/Neovim
├── snacks-animated-scrolling-off.lua
├── distant.lua               # edição remota (distant.nvim)
└── example.lua               # exemplo do starter (no-op)
lazyvim.json       # extras habilitados
lazy-lock.json     # versões dos plugins travadas (reprodutibilidade)
plugin/after/transparency.lua  # fundo transparente nos highlight groups
```

---

## 🎨 Arquivos gerados na máquina (NÃO versionados)

Estes existem em `~/.config/nvim/` mas **não** estão no repo — são específicos da máquina/sessão:

- **`lua/plugins/theme.lua`** → symlink para `~/.config/omarchy/current/theme/neovim.lua`. O tema é gerenciado pelo **Omarchy**; o `omarchy-theme-hotreload.lua` o recarrega ao trocar de tema. Recriado pelo Omarchy na máquina nova e ignorado via `.gitignore` deste diretório (`lua/plugins/theme.lua`), para nunca ser commitado mesmo que o stow folde a pasta.
- **`lazy/`, `mason/`** ficam em `~/.local/share/nvim/` (não em `~/.config`), portanto fora deste repo por natureza.

---

## 🔑 Notas

- **intelephense**: features premium pedem licença (`intelephense.licenceKey`); o tier grátis cobre o essencial.
- **live-server**: serve a partir do diretório de trabalho do nvim (`:pwd`). Abra o nvim na raiz do projeto (ou `:cd` antes).
- Diagnóstico geral: `:checkhealth`, `:Lazy`, `:Mason`, `:LspInfo`.
