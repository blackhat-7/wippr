/// Shell vocabulary for command mode: names of common commands, and the prompt that primes Whisper with them.
/// Built in, so terminals work with no setup.
enum ShellVocabulary {
    static let commands = """
    git sudo cd ls cat grep rg find fd cp mv rm mkdir rmdir touch chmod chown echo export source ssh scp rsync curl wget \
    tar zip unzip make just nix brew apt dnf pacman npm npx yarn pnpm node bun deno python python3 pip pip3 uv cargo \
    rustc go gradle mvn docker kubectl helm terraform tmux vim nvim nano emacs code less head tail sort uniq wc cut sed \
    awk xargs jq ps top htop kill pkill killall df du free uname whoami which man history clear exit systemctl \
    journalctl service ping ip lsof env date sleep watch tee diff gh fzf bat eza zoxide stow direnv pytest ruby gem \
    bundle php psql mysql sqlite3 openssl gpg crontab zsh bash fish gcloud gsutil aws az tailscale claude opencode \
    codex zed nvm uvx direnv pbcopy pbpaste pgrep netstat ffmpeg exiftool packer playwright pre-commit lazygit \
    kubectx k9s ansible vagrant htop btop tldr starship atuin
    """.split(separator: " ").map(String.init)

    /// Whisper copies its prompt's style: symbols written as words (`SpokenSymbols` turns them into characters),
    /// commands as separate words, and these names spelled as commands. None of this is from the benchmark's cases.
    static let whisperPrompt = "git pull dash dash rebase double and git log. cd tilde slash projects slash app. "
        + "ls dash l h pipe grep notes. cat config dot yaml. sudo reboot. control b c. Commands: "
        + commands.prefix(60).joined(separator: ", ") + "."
}
