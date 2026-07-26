-- quarto-nvim's runner calls otter's get_current_language_context() *before*
-- sync_raft() (which is what would normally repair a stale otter buffer), so if
-- otter's hidden language buffer ever gets wiped out from under it, run_cell/etc.
-- crash instead of recovering. Re-activate otter and retry once instead of leaving
-- the user stuck needing a manual :e! every time it happens.
local function run_with_otter_recovery(fn)
  return function()
    local ok, err = pcall(fn)
    if not ok then
      vim.notify("[quarto] otter buffer went stale, re-activating: " .. tostring(err), vim.log.levels.WARN)
      pcall(require("otter").activate)
      fn()
    end
  end
end

-- Long-lived shells under nested multiplexers (herdr, tmux, ...) inherit
-- $WEZTERM_UNIX_SOCKET at spawn time. If the WezTerm GUI app itself gets
-- restarted afterward, that socket path points at a dead process and
-- wezterm.nvim's `wezterm cli split-pane` calls fail - sometimes dumping raw
-- error output into the terminal and corrupting the screen mid-redraw.
-- Self-heal by pointing at whatever WezTerm GUI is actually alive right now.
local function fix_stale_wezterm_socket()
  local sock = vim.env.WEZTERM_UNIX_SOCKET
  if sock and vim.uv.fs_stat(sock) then
    return -- already valid
  end
  local pid = vim.fn.systemlist("pgrep -x wezterm-gui")[1]
  if not pid or pid == "" then
    return -- not running under a real WezTerm GUI at all
  end
  local candidate = vim.fn.expand("~/.local/share/wezterm/gui-sock-" .. pid)
  if vim.uv.fs_stat(candidate) then
    vim.env.WEZTERM_UNIX_SOCKET = candidate
  end
end

return {
  -- ── Kernel execution + inline output ────────────────────────────────
  {
    "benlubas/molten-nvim",
    version = "^1.0.0", -- stay on 1.x to avoid breaking changes
    lazy = false, -- it's a remote (python) plugin; lazy-loading hides its commands
    build = ":UpdateRemotePlugins",
    dependencies = {
      "willothy/wezterm.nvim", -- renders images via `wezterm imgcat` in a split pane
    },
    init = function()
      -- g:python3_host_prog is set by home.nix's `neovim.override { withPython3 = true; }`,
      -- baked into the nvim wrapper's own early --cmd so it's ready before init.lua even
      -- loads. Setting it here from Lua would be too late: Neovim's python3 provider
      -- detection runs before *any* user config gets a chance to run.

      fix_stale_wezterm_socket()

      -- image.nvim's kitty-protocol backend isn't officially supported under WezTerm
      -- (perf issues, partial compliance). wezterm.nvim shells out to `wezterm imgcat`
      -- in a split pane instead, which is reliable on this setup.
      vim.g.molten_image_provider = "wezterm"

      -- Always-visible output, VS Code style, instead of a floating window that only
      -- shows while the cursor sits in the cell.
      vim.g.molten_virt_text_output = true
      vim.g.molten_virt_lines_off_by_1 = true
      vim.g.molten_auto_open_output = false
      vim.g.molten_wrap_output = true
      vim.g.molten_output_win_max_height = 20

      vim.api.nvim_create_user_command("NewNotebook", function(cmd_opts)
        local path = cmd_opts.args:match("%.ipynb$") and cmd_opts.args or (cmd_opts.args .. ".ipynb")
        local notebook = {
          cells = {
            {
              cell_type = "code",
              metadata = vim.empty_dict(),
              source = {},
              outputs = {},
              execution_count = vim.NIL,
            },
          },
          metadata = {
            kernelspec = { display_name = "Python 3", language = "python", name = "python3" },
            language_info = { name = "python" },
          },
          nbformat = 4,
          nbformat_minor = 5,
        }
        vim.fn.writefile({ vim.fn.json_encode(notebook) }, path)
        vim.cmd.edit(path)
      end, { nargs = 1, complete = "file", desc = "Create a blank Jupyter notebook" })
    end,
    keys = {
      {
        "<leader>mi",
        function()
          -- Auto-pick the kernel matching the active venv/conda env, like VS Code's
          -- "select interpreter" remembering your last choice. Falls back to a prompt.
          local venv = os.getenv("VIRTUAL_ENV") or os.getenv("CONDA_PREFIX")
          local kernels = vim.fn.MoltenAvailableKernels()
          local name = venv and vim.tbl_contains(kernels, venv:match("([^/]+)$")) and venv:match("([^/]+)$")
          if name then
            vim.cmd.MoltenInit(name)
          else
            vim.cmd.MoltenInit()
          end
        end,
        desc = "Init Kernel (auto-detect venv)",
      },
      { "<leader>mI", "<cmd>MoltenInit<cr>", desc = "Init Kernel (prompt)" },
      { "<leader>ml", "<cmd>MoltenEvaluateLine<cr>", desc = "Evaluate Line" },
      { "<leader>me", "<cmd>MoltenEvaluateOperator<cr>", desc = "Evaluate Operator" },
      { "<leader>me", ":<C-u>MoltenEvaluateVisual<cr>gv", mode = "v", desc = "Evaluate Selection" },
      { "<leader>mr", "<cmd>MoltenReevaluateCell<cr>", desc = "Re-evaluate Cell" },
      { "<leader>md", "<cmd>MoltenDelete<cr>", desc = "Delete Cell" },
      {
        "<leader>mn",
        function()
          local row = vim.api.nvim_win_get_cursor(0)[1]
          vim.api.nvim_buf_set_lines(0, row, row, false, { "", "```python", "", "```" })
          vim.api.nvim_win_set_cursor(0, { row + 3, 0 })
          vim.cmd.startinsert()
        end,
        desc = "New Cell Below",
      },
      { "<leader>mo", "<cmd>noautocmd MoltenEnterOutput<cr>", desc = "Enter Output" },
      { "<leader>mh", "<cmd>MoltenHideOutput<cr>", desc = "Hide Output" },
      { "<leader>mx", "<cmd>MoltenInterrupt<cr>", desc = "Interrupt Kernel" },
      { "<leader>mR", "<cmd>MoltenRestart!<cr>", desc = "Restart Kernel (clear outputs)" },
    },
  },

  -- ── Open/save .ipynb as a markdown cell buffer (LSP, formatting, etc. work) ──
  {
    "GCBallesteros/jupytext.nvim",
    lazy = false, -- lazy-loading can leave you staring at raw notebook JSON
    opts = {
      style = "markdown",
      output_extension = "md",
      force_ft = "markdown",
    },
  },

  -- ── LSP features (completion, hover, diagnostics) inside code cells ──────
  {
    "quarto-dev/quarto-nvim",
    ft = { "quarto", "markdown" },
    dependencies = { "jmbuhr/otter.nvim" },
    opts = {
      lspFeatures = {
        languages = { "python" },
        chunks = "all", -- plain ```python fences, not quarto's {python} chunks
        diagnostics = { enabled = true, triggers = { "BufWritePost" } },
        completion = { enabled = true },
      },
      codeRunner = {
        enabled = true,
        default_method = "molten",
      },
    },
    keys = {
      { "<leader>rc", run_with_otter_recovery(function() require("quarto.runner").run_cell() end), desc = "Run Cell" },
      { "<leader>ra", run_with_otter_recovery(function() require("quarto.runner").run_above() end), desc = "Run Cell + Above" },
      { "<leader>rA", run_with_otter_recovery(function() require("quarto.runner").run_all() end), desc = "Run All Cells" },
      { "<leader>rl", run_with_otter_recovery(function() require("quarto.runner").run_line() end), desc = "Run Line" },
      { "<leader>r", run_with_otter_recovery(function() require("quarto.runner").run_range() end), mode = "v", desc = "Run Selection" },
    },
  },

}
