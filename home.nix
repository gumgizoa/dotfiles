{ config, pkgs, user, ... }:

let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
in

{
  home.username = user;
  home.homeDirectory = "/Users/${user}";
  home.stateVersion = "24.11";
  home.packages = with pkgs; [
    # cli i use constantly
    ripgrep   # fast search
    fd        # fast find
    fzf       # fuzzy finder
    jq        # json on the command line
    lazygit
    uv        # python project/venv manager (bicquant etc. use it)
    (neovim.override {
      viAlias = true;
      # plain `neovim` disables g:loaded_python3_provider in its wrapper script's
      # --cmd, which runs *before* init.lua ever loads - no amount of setting
      # vim.g.python3_host_prog from Lua can undo that. Must be enabled here.
      withPython3 = true;
      extraPython3Packages = ps: with ps; [
        pynvim         # nvim's python3 remote-plugin host (molten is a remote plugin)
        jupyter-client # talks to jupyter kernels, used by molten's rplugin code
      ];
    })
    nodejs    # needed by mason for npm-based LSP servers (vtsls, etc.)
    tree-sitter  # CLI needed by nvim-treesitter to compile parsers
    # CLI tools shelled out to by nvim, not part of nvim's own python3 host
    (python3.withPackages (ps: with ps; [
      jupytext  # ipynb <-> markdown conversion CLI, used by jupytext.nvim
      ipykernel # registers a project venv as a kernel: `python -m ipykernel install --user --name <venv>`
    ]))
    # the font everything renders in
    nerd-fonts.hack
  ];
  fonts.fontconfig.enable = true;
  home.sessionVariables.EDITOR = "nvim";

  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;      # ghost text from history
    syntaxHighlighting.enable = true;  # commands turn green when valid
    initContent = ''
      bindkey '^f' autosuggest-accept
      # rustup is keg-only (conflicts with the rust formula), so its bin isn't symlinked into /opt/homebrew/bin.
      export PATH="/opt/homebrew/opt/rustup/bin:$PATH"
    '';
    shellAliases = {
      ".." = "cd ..";
      add = "git add .";
      push = "git push";
      pull = "git pull";
      m = "git switch main";
      cc = "claude --dangerously-skip-permissions";
      co = "codex --full-auto";
    };
  };

  programs.starship = {
    enable = true;
    settings = {
      add_newline = false;
      format = "$directory$git_branch$git_status$cmd_duration$line_break$character";
      character = {
        success_symbol = "[❯](purple)";
        error_symbol = "[❯](red)";
      };
      cmd_duration.format = "[$duration]($style) ";
    };
  };

  # Edit-in-place: the real file stays in my repo, ~/.config just points at it.
  home.file.".config/wezterm".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/wezterm";
  home.file.".config/nvim".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/nvim";
  home.file.".config/herdr".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/herdr";
  home.file.".claude/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.claude/settings.json";
  home.file.".omp/agent/config.yml".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.omp/agent/config.yml";

  home.file.".claude/CLAUDE.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
  home.file.".codex/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
  home.file.".config/opencode/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
  home.file.".omp/agent/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
}
