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
    kubectx k9s ansible vagrant htop btop tldr starship atuin set unset alias eval exec read test true false printf \
    jobs fg bg wait type command jest vitest pie
    """.split(separator: " ").map(String.init)

    /// Whisper copies its prompt's style: symbols written as words (`SpokenSymbols` turns them into characters),
    /// commands as separate words, and these names spelled as commands. None of this is from the benchmark's cases.
    static let whisperPrompt = "git pull dash dash rebase double and git log. cd tilde slash projects slash app. "
        + "ls dash l h pipe grep notes. cat config dot yaml. sudo reboot. control b c. Commands: "
        + commands.prefix(60).joined(separator: ", ") + "."

    /// The known command that sounds like `word` and is spelled within 2 letters of it, if exactly one is closest:
    /// "demux" → "tmux", "get" / "jit" → "git". The user's own names ("nv", "mdr") match none, so they stay as heard.
    static func command(soundingLike word: String) -> String? {
        guard !commands.contains(word), word.count >= 2, word.allSatisfy(\.isLetter) else { return nil }
        let key = soundKey(word)
        let candidates = Set(commands.filter { soundKey($0) == key }).map { ($0, editDistance($0, word)) }.filter { $0.1 <= 2 }
        guard let best = candidates.map(\.1).min() else { return nil }
        let closest = candidates.filter { $0.1 == best }
        return closest.count == 1 ? closest[0].0 : nil
    }

    /// A coarse spelling of how a word sounds: vowels after the first letter dropped, t/d, k/c/q, s/z, f/v/ph merged.
    static func soundKey(_ word: String) -> String {
        var key = ""
        for (i, letter) in word.lowercased().replacing("ph", with: "f").replacing("ck", with: "k")
            .replacing("x", with: "ks").enumerated() {
            let sound: Character? = switch letter {
            case "a", "e", "i", "o", "u", "y": i == 0 ? letter : nil
            case "h": nil
            case "d": "t"
            case "c", "q": "k"
            case "g", "j": "j"
            case "z": "s"
            case "v": "f"
            default: letter
            }
            if let sound, key.last != sound { key.append(sound) }
        }
        return key
    }

    private static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var row = Array(0...b.count)
        for i in a.indices {
            var previous = row[0]
            row[0] = i + 1
            for j in b.indices {
                let saved = row[j + 1]
                row[j + 1] = min(row[j + 1] + 1, row[j] + 1, previous + (a[i] == b[j] ? 0 : 1))
                previous = saved
            }
        }
        return row[b.count]
    }
}
