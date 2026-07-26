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
      -- The neovim host that runs molten's glue code. Not to be confused with
      -- a notebook's *kernel*, which is whatever interpreter the code actually runs in.
      vim.g.python3_host_prog = vim.fn.exepath("python3")

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
      { "<leader>rc", function() require("quarto.runner").run_cell() end, desc = "Run Cell" },
      { "<leader>ra", function() require("quarto.runner").run_above() end, desc = "Run Cell + Above" },
      { "<leader>rA", function() require("quarto.runner").run_all() end, desc = "Run All Cells" },
      { "<leader>rl", function() require("quarto.runner").run_line() end, desc = "Run Line" },
      { "<leader>r", function() require("quarto.runner").run_range() end, mode = "v", desc = "Run Selection" },
    },
  },

}
