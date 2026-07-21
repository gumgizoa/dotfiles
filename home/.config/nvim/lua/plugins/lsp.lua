return {
  -- ── Formatter ────────────────────────────────────────────────────────
  {
    "stevearc/conform.nvim",
    event = { "BufWritePre" },
    cmd = "ConformInfo",
    opts = {
      formatters_by_ft = {
        javascript = { "prettierd" },
        javascriptreact = { "prettierd" },
        typescript = { "prettierd" },
        typescriptreact = { "prettierd" },
        json = { "prettierd" },
        jsonc = { "prettierd" },
        css = { "prettierd" },
        html = { "prettierd" },
        markdown = { "prettierd" },
        yaml = { "prettierd" },
        python = { "ruff_organize_imports", "ruff_format" },
        lua = { "stylua" },
      },
      format_on_save = {
        timeout_ms = 500,
        lsp_format = "fallback",
      },
    },
  },

  -- ── Non-LSP tools installed via Mason ────────────────────────────────
  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    event = "VeryLazy",
    dependencies = { "mason-org/mason.nvim" },
    opts = {
      ensure_installed = { "prettierd", "stylua" },
      run_on_start = true,
    },
  },

  -- ── Mason + LSP ──────────────────────────────────────────────────────
  {
    "mason-org/mason-lspconfig.nvim",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = {
      { "mason-org/mason.nvim", opts = { ui = { border = "rounded" } } },
      "neovim/nvim-lspconfig",
    },
    config = function()
      ---------------------------------------------------------------------
      -- Per-server configuration
      -- Must run before mason-lspconfig.setup() enables the servers.
      ---------------------------------------------------------------------

      -- TypeScript / JavaScript
      vim.lsp.config("ts_ls", {
        settings = {
          typescript = {
            inlayHints = {
              includeInlayParameterNameHints = "literals",
              includeInlayParameterNameHintsWhenArgumentMatchesName = false,
              includeInlayFunctionParameterTypeHints = true,
              includeInlayVariableTypeHints = true,
              includeInlayVariableTypeHintsWhenTypeMatchesName = false,
              includeInlayPropertyDeclarationTypeHints = true,
              includeInlayFunctionLikeReturnTypeHints = true,
              includeInlayEnumMemberValueHints = true,
            },
          },
          javascript = {
            inlayHints = {
              includeInlayParameterNameHints = "all",
              includeInlayFunctionParameterTypeHints = true,
              includeInlayVariableTypeHints = true,
              includeInlayFunctionLikeReturnTypeHints = true,
            },
          },
        },
      })

      -- ESLint: auto-fix on save
      vim.lsp.config("eslint", {
        on_attach = function(_, bufnr)
          vim.api.nvim_create_autocmd("BufWritePre", {
            buffer = bufnr,
            command = "EslintFixAll",
          })
        end,
      })

      -- Python: type checking, completion, inlay hints
      vim.lsp.config("basedpyright", {
        settings = {
          basedpyright = {
            analysis = {
              typeCheckingMode = "standard",
              autoSearchPaths = true,
              useLibraryCodeForTypes = true,
              diagnosticMode = "openFilesOnly",
              inlayHints = {
                variableTypes = true,
                functionReturnTypes = true,
                callArgumentNames = true,
                genericTypes = false,
              },
            },
          },
        },
      })

      -- Python: linting and formatting
      vim.lsp.config("ruff", {
        init_options = {
          settings = { lineLength = 88 },
        },
        on_attach = function(client)
          -- Let basedpyright own hover so the two servers don't conflict
          client.server_capabilities.hoverProvider = false
        end,
      })

      -- Lua (for editing this Neovim config)
      vim.lsp.config("lua_ls", {
        settings = {
          Lua = {
            runtime = { version = "LuaJIT" },
            diagnostics = { globals = { "vim" } },
            workspace = {
              library = vim.api.nvim_get_runtime_file("", true),
              checkThirdParty = false,
            },
            hint = { enable = true },
            telemetry = { enable = false },
          },
        },
      })

      ---------------------------------------------------------------------
      -- Install servers and auto-enable them
      ---------------------------------------------------------------------
      require("mason-lspconfig").setup({
        ensure_installed = {
          "ts_ls",
          "eslint",
          "basedpyright",
          "ruff",
          "lua_ls",
        },
        automatic_enable = true,
      })

      ---------------------------------------------------------------------
      -- Keymaps, applied per buffer when a server attaches
      ---------------------------------------------------------------------
      vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(ev)
          local client = vim.lsp.get_client_by_id(ev.data.client_id)
          local map = function(mode, keys, fn, desc)
            vim.keymap.set(mode, keys, fn, { buffer = ev.buf, desc = "LSP: " .. desc })
          end

          -- Navigation. Use <C-o> to jump back.
          map("n", "gd", vim.lsp.buf.definition, "Goto Definition")
          map("n", "gD", vim.lsp.buf.declaration, "Goto Declaration")
          map("n", "gi", vim.lsp.buf.implementation, "Goto Implementation")
          map("n", "gy", vim.lsp.buf.type_definition, "Goto Type Definition")
          map("n", "gr", vim.lsp.buf.references, "List References")

          -- Info and edits
          map("n", "K", vim.lsp.buf.hover, "Hover Documentation")
          map("n", "<leader>rn", vim.lsp.buf.rename, "Rename Symbol")
          map({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, "Code Action")
          map("n", "<leader>ds", vim.lsp.buf.document_symbol, "Document Symbols")

          -- Diagnostics
          map("n", "[d", function() vim.diagnostic.jump({ count = -1 }) end, "Prev Diagnostic")
          map("n", "]d", function() vim.diagnostic.jump({ count = 1 }) end, "Next Diagnostic")
          map("n", "<leader>e", vim.diagnostic.open_float, "Show Diagnostic")

          -- Inlay hints: on by default, toggleable
          if client and client:supports_method("textDocument/inlayHint") then
            vim.lsp.inlay_hint.enable(true, { bufnr = ev.buf })
            map("n", "<leader>th", function()
              vim.lsp.inlay_hint.enable(
                not vim.lsp.inlay_hint.is_enabled({ bufnr = ev.buf }),
                { bufnr = ev.buf }
              )
            end, "Toggle Inlay Hints")
          end
        end,
      })

      ---------------------------------------------------------------------
      -- Diagnostic display
      ---------------------------------------------------------------------
      vim.diagnostic.config({
        virtual_text = { prefix = "●" },
        severity_sort = true,
        underline = true,
        update_in_insert = false,
        float = { border = "rounded", source = true },
        signs = {
          text = {
            [vim.diagnostic.severity.ERROR] = " ",
            [vim.diagnostic.severity.WARN] = " ",
            [vim.diagnostic.severity.HINT] = " ",
            [vim.diagnostic.severity.INFO] = " ",
          },
        },
      })
    end,
  },
}
