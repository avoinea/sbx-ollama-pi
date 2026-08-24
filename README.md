# sbx-ollama-pi

Custom template image for running [pi](https://pi.dev) inside Docker Sandboxes ([`sbx`](https://docs.docker.com/reference/cli/sbx/)), with [Ollama](https://ollama.com) as the model provider.
___

> Docker Sandboxes (`sbx`) are a nice way to run coding agents with a bit more isolation and a bit less YOLO. There's no "official" support for pi yet (see supported agents [`sbx create` docs](https://docs.docker.com/reference/cli/sbx/create/)), but it's easy to add via a custom template image.

**Note**: Docker also has a `docker sandbox` command that overlaps with `sbx`, but it seems to lag behind in features. I recommend sticking to `sbx`. This FAQ section was especially useful for passing custom environment variables: [How do I set custom environment variables inside a sandbox?](https://docs.docker.com/ai/sandboxes/faq/#how-do-i-set-custom-environment-variables-inside-a-sandbox).


## The Images

The [Dockerfile](./Dockerfile) extends the `shell` template, installs [Ollama](https://ollama.com), [nvm](https://github.com/nvm-sh/nvm) with Node.js 22 and 24, and `pi`, and tweaks `~/.bashrc` to auto-launch `pi` via `ollama launch pi`. The default model is `glm-5.2:cloud` from Ollama with thinking level set to `xhigh` (mapped to `max` via `thinkingLevelMap` in [models.json](./models.json)).

Published on Docker Hub:
- `avoinea/sbx-ollama-pi`
- `avoinea/sbx-ollama-pi:docker`

There is also a [Dockerfile.shell-docker](./Dockerfile.shell-docker) file whose only difference is that it uses the [shell-docker](https://hub.docker.com/layers/docker/sandbox-templates/shell-docker/images/) image. With this image, the agent has access to **its own docker daemon**.

## How It Works

The image uses [`ollama launch pi`](https://docs.ollama.com/integrations/pi) — Ollama's built-in integration for pi. When the sandbox starts, `.bashrc` runs:

```bash
ollama launch pi --model="${PI_MODEL:-glm-5.2:cloud}" --yes
```

This single command handles:
- Starting the Ollama server
- Configuring `~/.pi/agent/models.json` and `settings.json` with the Ollama provider
- Detecting model capabilities (vision, thinking, context window) via Ollama's API
- Installing/updating the `@ollama/pi-web-search` package
- Launching pi with the configured model

**Note:** `ollama launch pi` does not set `defaultThinkingLevel` in `settings.json`, `reasoning: true` in `models.json`, or `thinkingLevelMap` — all are required for thinking to work. The image pre-seeds these files ([settings.json](./settings.json), [models.json](./models.json)) during build. `ollama launch pi` merges into them on each run, preserving the pre-seeded values.

The `thinkingLevelMap` in `models.json` maps pi's thinking levels to the model's actual levels. For `glm-5.2:cloud`, `xhigh` maps to `max` (the model's highest level), since `xhigh` is not natively supported.

When you `/quit` pi, you fall back to a bash shell. Run `ollama launch pi` again to relaunch.

### Network Policy

The sandbox's network policy blocks outbound connections by default. The domains you need to allow depend on your setup:

| Setup | Allow rule |
|-------|------------|
| In-image Ollama (cloud models) | `sbx policy allow network ollama.com` |
| Host Ollama via `OLLAMA_URL` | `sbx policy allow network localhost:11434` |

Alternatively, use the Open preset to allow all traffic:
```bash
sbx policy init allow-all
```

### Authentication

Cloud models (like `glm-5.2:cloud`) require Ollama Cloud authentication. On first launch, if you haven't authenticated, the auto-launch will automatically run `ollama signin` to link your [ollama.com](https://ollama.com) account. Follow the prompts to complete sign-in, then pi will launch automatically.

This is separate from pi's `/login`. The `ollama signin` command authenticates the local Ollama server with Ollama Cloud, so cloud model requests are automatically authenticated.

### Overriding the Default Model

Set the `PI_MODEL` environment variable to use a different model at launch:

```bash
sbx run -e PI_MODEL=minimax-m3:cloud -t avoinea/sbx-ollama-pi shell [PROJECT_DIR]
```

### Overriding the Default Thinking Level

Set the `PI_THINKING` environment variable to use a different thinking level (default: `xhigh`):

```bash
sbx run -e PI_THINKING=high -t avoinea/sbx-ollama-pi shell [PROJECT_DIR]
```

Valid thinking levels: `off`, `minimal`, `low`, `medium`, `high`, `xhigh`, `max`. Note that `xhigh` maps to `max` for `glm-5.2:cloud` via `thinkingLevelMap`.

Cloud models are listed at [ollama.com/search?c=cloud](https://ollama.com/search?c=cloud). Some models support vision (image input) — useful for browser automation with Playwright:

| Model | Vision | Context | Thinking |
|-------|--------|---------|----------|
| `glm-5.2:cloud` (default) | ❌ | 1,000,000 | ✅ |
| `minimax-m3:cloud` | ✅ | 524,288 | ✅ |
| `kimi-k3:cloud` | ✅ | 1,048,576 | ✅ |

### Customizing pi

Place a `.pi/agent/` directory in your project root to override or extend the pre-seeded pi configuration. On startup, the sandbox merges it into `~/.pi/agent/` — files you provide override the pre-seeded ones, files you don't provide are kept.

This lets you customize everything pi supports:

```
my-project/
├── .pi/
│   └── agent/
│       ├── models.json      ← custom models, thinkingLevelMap, reasoning flags
│       ├── settings.json    ← custom defaultThinkingLevel, packages, theme
│       └── skills/           ← custom skills
├── src/
└── ...
```

When providing a custom `models.json`, make sure to include `"reasoning": true` on models that support thinking, otherwise pi will not enable thinking even with `defaultThinkingLevel` set.

### Using a Remote Ollama Server

If you have Ollama running on your host, use `host.docker.internal` to reach it from inside the sandbox (not `localhost`, which refers to the sandbox itself):

```bash
sbx policy allow network localhost:11434
sbx run -e OLLAMA_HOST=http://host.docker.internal:11434 -t avoinea/sbx-ollama-pi shell [PROJECT_DIR]
```

**Why `localhost:11434` in the policy?** The sbx proxy translates `host.docker.internal` to `localhost` before forwarding the request, so the network policy check is against `localhost` with the specific port.

## Usage

1. Install `sbx`: https://docs.docker.com/ai/sandboxes/

2. Allow Ollama Cloud access (one-time):
```bash
sbx policy allow network ollama.com
```

3. Run the template image:
```bash
sbx run -t avoinea/sbx-ollama-pi shell [PROJECT_DIR]
```
_OR_ with in-sandbox Docker daemon:
```bash
sbx run -t avoinea/sbx-ollama-pi:docker shell [PROJECT_DIR]
```

On first launch, `ollama signin` will automatically prompt you to authenticate with your ollama.com account. After that, pi launches with `glm-5.2:cloud` and thinking level `xhigh` (mapped to `max`). When you `/quit` pi, you get a bash shell.

## Node.js Versions

The image includes [nvm](https://github.com/nvm-sh/nvm) with Node.js 22 (default) and 24 installed. Switch at runtime with:

```bash
nvm use 22
nvm use 24
```

`pi` is installed under both Node versions, so it works regardless of which version is active.

Override the default at build time:
```bash
docker build --build-arg NODE_DEFAULT=24 -t avoinea/sbx-ollama-pi .
```

## Updating the Image

To build and push manually:

```bash
docker build -t avoinea/sbx-ollama-pi --push .
```

Default Node version is 22. Override with `--build-arg NODE_DEFAULT=24`:
```bash
docker build --build-arg NODE_DEFAULT=24 -t avoinea/sbx-ollama-pi --push .
```

OR for the shell-docker variant:
```bash
docker build -t avoinea/sbx-ollama-pi:docker --push -f Dockerfile.shell-docker .
```

## Acknowledgements

This is a fork of [geut/sbx-shell-pi](https://github.com/geut/sbx-shell-pi), originally based on Oleg Šelajev's article [Building custom Docker Sandboxes](https://olegselajev.substack.com/p/building-custom-docker-sandboxes). ~~One key difference: local images never worked for me. `sbx save` completes, but referencing a local image fails. sbx appears to look up the image in a registry instead (you can see this by inspecting `sbx daemon` output).~~