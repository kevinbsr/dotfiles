# ─── Starship Prompt ───────────────────────────────
if type -q starship
    starship init fish | source
end

# ─── Disable Greeting ──────────────────────────────
set -g fish_greeting

# ─── Run Fastfetch on Startup ──────────────────────
if type -q fastfetch
    fastfetch
end

# ─── Aliases ───────────────────────────────────────
alias ll="ls -lah"
alias g="git"
alias v="nvim"
alias cat="bat"
alias launcher="wofi --show drun --conf ~/.config/wofi/config --style ~/.config/wofi/style.css"
alias power="~/.config/wofi/scripts/power.sh"
alias emoji="~/.config/wofi/scripts/emoji.sh"
alias restart_wofi='pkill wofi && wofi --show drun --conf ~/.config/wofi/config --style ~/.config/wofi/style.css'
alias ff="fastfetch"

# ─── Auto Tab Title ────────────────────────────────
function update_tab_title --on-event fish_prompt
    set -l title (basename (pwd))

    if test -n "$VIRTUAL_ENV"
        set title "🐍 venv: $title"
    end

    if type -q git
        set -l git_branch (git rev-parse --abbrev-ref HEAD ^/dev/null 2>/dev/null)
        if test -n "$git_branch"
            set title "$title ⎇ $git_branch"
        end
    end

    if status is-interactive
        printf "\033]2;%s\007" "$title"
    end
end
