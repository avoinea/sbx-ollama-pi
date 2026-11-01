# sbx-ollama-pi

Custom template image for running [pi](https://pi.dev) inside Docker Sandboxes ([`sbx`](https://docs.docker.com/reference/cli/sbx/)), with [Ollama](https://ollama.com) as the model provider.
___

> Docker Sandboxes (`sbx`) are a nice way to run coding agents with a bit more isolation and a bit less YOLO. There's no "official" support for pi yet (see supported agents [`sbx create` docs](https://docs.docker.com/reference/cli/sbx/create/)), but it's easy to add via a custom template image.

**Note**: Docker also has a `docker sandbox` command that overlaps with `sbx`, but it seems to lag behind in features. I recommend sticking to `sbx`. This FAQ section was especially useful for passing custom environment variables: [How do I set custom environment variables inside a sandbox?](https://docs.docker.com/ai/sandboxes/faq/#how-do-i-set-custom-environment-variables-inside-a-sandbox).


## The Images

The [Dockerfile](./Dockerfile) extends the `shell` template, installs [Ollama](https://ollama.com), [nvm](https://github.com/nvm-sh/nvm) with Node.js 22 and 24, and `pi`, plus `t3` for [T3 Code](#using-with-t3-code), and tweaks `~/.bashrc` to auto-launch `pi` via `ollama launch pi`. The default model is `deepseek-v4.1-flash:1017-cloud` from Ollama with thinking level set to `max` (see [settings.json](./settings.json) and [models.json](./models.json)).

Published on Docker Hub:
- `avoinea/sbx-ollama-pi`
- `avoinea/sbx-ollama-pi:docker`

There is also a [Dockerfile.shell-docker](./Dockerfile.shell-docker) file whose only difference is that it uses the [shell-docker](https://hub.docker.com/layers/docker/sandbox-templates/shell-docker/images/) image. With this image, the agent has access to **its own docker daemon**.

## How It Works

The image uses [`ollama launch pi`](https://docs.ollama.com/integrations/pi) — Ollama's built-in integration for pi. When the sandbox starts, `.bashrc` runs:

```bash
ollama launch pi --model="${PI_MODEL:-deepseek-v4.1-flash:1017-cloud}" --yes
```

This single command handles:
- Starting the Ollama server
- Configuring `~/.pi/agent/models.json` and `settings.json` with the Ollama provider
- Detecting model capabilities (vision, thinking, context window) via Ollama's API
- Installing/updating the `@ollama/pi-web-search` package
- Launching pi with the configured model

**Note:** `ollama launch pi` does not set `defaultThinkingLevel` in `settings.json`, `reasoning: true` in `models.json`, or `thinkingLevelMap` — all are required for thinking to work. The image pre-seeds these files ([settings.json](./settings.json), [models.json](./models.json)) during build. `ollama launch pi` merges into them on each run, preserving the pre-seeded values.

The `thinkingLevelMap` in `models.json` maps pi's thinking levels to the model's actual levels. `deepseek-v4.1-flash:1017-cloud` natively supports `off`, `low`, `high` and `max`; `xhigh` is mapped to `max` as well, while `minimal` and `medium` are marked as unsupported.

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

Cloud models (like `deepseek-v4.1-flash:1017-cloud`) require Ollama Cloud authentication. On first launch, if you haven't authenticated, the auto-launch will automatically run `ollama signin` to link your [ollama.com](https://ollama.com) account. Follow the prompts to complete sign-in, then pi will launch automatically.

This is separate from pi's `/login`. The `ollama signin` command authenticates the local Ollama server with Ollama Cloud, so cloud model requests are automatically authenticated.

### Overriding the Default Model

Set the `PI_MODEL` environment variable to use a different model at launch:

```bash
sbx run -e PI_MODEL=glm-5.3-flash:cloud -t avoinea/sbx-ollama-pi shell [PROJECT_DIR]
```

### Overriding the Default Thinking Level

Set the `PI_THINKING` environment variable to use a different thinking level (default: `max`):

```bash
sbx run -e PI_THINKING=high -t avoinea/sbx-ollama-pi shell [PROJECT_DIR]
```

Valid thinking levels: `off`, `minimal`, `low`, `medium`, `high`, `xhigh`, `max`. Note that `xhigh` maps to `max` for `deepseek-v4.1-flash:1017-cloud` via `thinkingLevelMap`.

Cloud models are listed at [ollama.com/search?c=cloud](https://ollama.com/search?c=cloud). Some models support vision (image input) — useful for browser automation with Playwright:

| Model | Vision | Context | Thinking |
|-------|--------|---------|----------|
| `deepseek-v4.1-flash:1017-cloud` (default) | ✅ | 1,048,576 | ✅ |
| `glm-5.3-flash:cloud` | ✅ | 1,048,576 | ✅ |
| `minimax-m3:cloud` | ✅ | 524,288 | ✅ |
| `kimi-k3:cloud` | ✅ | 1,048,576 | ✅ |

### Customizing pi

Place a `.pi/agent/` directory in your project root — the directory you pass to `sbx run`, available inside the sandbox as `$WORKSPACE_DIR` — to override or extend the pre-seeded pi configuration. On startup, the sandbox merges it into `~/.pi/agent/` — files you provide override the pre-seeded ones, files you don't provide are kept.

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

On first launch, `ollama signin` will automatically prompt you to authenticate with your ollama.com account. After that, pi launches with `deepseek-v4.1-flash:1017-cloud` and thinking level `max`. When you `/quit` pi, you get a bash shell.

## Sandbox name and the `pi` kit

`sbx` names a sandbox `<agent>-<directory>`, where the first positional argument is the agent or kit you launch. `sbx run -t avoinea/sbx-ollama-pi shell [PROJECT_DIR]` creates `shell-<directory>`, because `shell` is the agent whose image you replace with `--template`.

The [pi](./pi/spec.yaml) directory is a minimal sandbox kit that names the agent `pi` and points at this image:

```bash
sbx run ./pi [PROJECT_DIR]      # creates pi-<directory>
```

It is the same sandbox as the `--template` form, with a different name. Push it to a registry to use it by reference:

```bash
sbx kit push ./pi docker.io/avoinea/pi:latest
sbx run avoinea/pi [PROJECT_DIR]
```

Kits can also carry the launch entrypoint, network permissions, setup steps, and agent instructions; see the [kit spec reference](https://docs.docker.com/ai/sandboxes/customize/kit-reference/). Everything in [Using with T3 Code](#using-with-t3-code) works the same with the kit.

[bin/pix](./bin/pix) wraps that: it names the sandbox `pi-<directory>` after the current directory, creates it from `avoinea/pi` the first time, and attaches to it on later runs.

```bash
ln -s "$PWD/bin/pix" ~/.local/bin/pix    # once
pix                                      # attach, or create pi-<directory>
PIX_KIT=avoinea/pi-docker pix            # the shell-docker variant, Docker inside
PIX_NAME=scratch pix                     # a fixed sandbox name
```

The kit reference is only passed at creation. `sbx` reads the agent from an existing sandbox's stored spec, so re-running `pix` in a directory always reattaches instead of recreating.

## Using with T3 Code

[T3 Code](https://t3.codes) is a desktop, web, and mobile client that drives coding agents — including [pi](https://pi.dev) — and can run them inside a Docker Sandbox. There is no dedicated `sbx` integration: T3 Code treats the sandbox as an ordinary SSH host, starts a T3 server inside it, and tunnels that back over the connection ([Docker docs](https://docs.docker.com/ai/sandboxes/integrations/t3-code/)).

The image is ready for that:

- `pi` and `t3` are installed under the nvm Node versions **and** linked into `~/.local/bin`, which is first on the image `PATH`. Non-interactive shells (`sh -lc`) — what T3 Code uses to start providers — find both.
- `libatomic1`, `curl`, `tar`, and `sha256sum` are installed, which the `t3` runtime that T3 Code downloads into `~/.t3/runtime/versions/` on the first connection needs.

Both Node 22.23.4 and the current `pi` (1.4.0) satisfy T3 Code's requirements for the Pi provider: Node.js 22.19 or newer and Pi 0.80.5 or newer.

### Setup

1. Enable SSH access to sandboxes once. It writes an `Include` to `~/.ssh/config` and needs no keys — authentication goes through the `sbx` daemon and your Docker login:

```bash
sbx setup ssh
```

2. Start the sandbox from this image:

```bash
sbx run -t avoinea/sbx-ollama-pi shell [PROJECT_DIR]
```

3. Find its name with `sbx ls`, then confirm the host works (the pattern is `<sandbox>.sbx`):

```bash
ssh shell-myproject.sbx
```

4. In T3 Code, open **Settings → Environments → Add environment**, choose **SSH**, and enter that host. Then add a project using the workspace path inside the sandbox — it is the directory you passed to `sbx run`, mounted at the same absolute path, e.g. `/Users/you/project` (see [Workspace path](#workspace-path)).

The first connection installs the T3 server inside the sandbox, so it takes a moment; later connections are fast.

### Workspace path

`sbx` bind-mounts the directory you launch from at its **host absolute path** and exports it as `WORKSPACE_DIR`. It does not mount it at `/home/agent/workspace` — the base image creates that directory, but it stays empty. So a sandbox can be started from any directory, and the project path is simply that directory:

```bash
sbx run -t avoinea/sbx-ollama-pi shell ~/sandbox/eea-website
# inside: cwd and $WORKSPACE_DIR are /Users/you/sandbox/eea-website

sbx exec shell-eea-website -- printenv WORKSPACE_DIR
```

Use the same path as the project directory in T3 Code. The auto-launch merges a project `.pi/agent/` from `$WORKSPACE_DIR`, so per-project pi config works from any workspace. Without a workspace argument there is no mount and `WORKSPACE_DIR` is unset; T3 Code still connects, but there is no project to open.

### Keep Ollama running

T3 Code starts `pi` directly, not through the interactive `.bashrc` auto-launch, so the in-sandbox Ollama server that `models.json` points at (`http://127.0.0.1:11434/v1`) has to be running while T3 uses it:

```bash
sbx exec shell-myproject -- sh -c 'setsid nohup ollama serve >/tmp/ollama.log 2>&1 &'
```

To use a host Ollama instead, allow `localhost:11434` and start the sandbox with `OLLAMA_HOST` (see [Using a Remote Ollama Server](#using-a-remote-ollama-server)), then point `baseUrl` in `.pi/agent/models.json` — or the project's `.pi/agent/models.json` — at that URL.

`PI_MODEL` and `PI_THINKING` only affect the interactive auto-launch. With T3 Code, pick the model in the composer, or override the pre-seeded `~/.pi/agent/` files from the project's `.pi/agent/` directory as described in [Customizing pi](#customizing-pi).

### Two things not to do

- **Don't add the `t3code` kit** (`--kit docker.io/sbx/t3code-kit:latest`). It installs `t3` as root into an npm prefix this image doesn't have and aborts sandbox creation with `t3: Too many levels of symbolic links`. `t3` is already in the image.
- **Don't use T3 Connect (`t3 connect`) from inside a sandbox.** That path needs outbound TCP 7844 (QUIC/UDP egress is disabled in `sbx`), an allow rule for the `h2.cftunnel.com` SNI the tunnel client dials, and SRV DNS records the sandbox resolver doesn't serve — and the sandbox has to stay running. The SSH environment above needs none of it.

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

## CI/CD (GitHub Actions)

On every push to `main` (and on `v*` tags), [.github/workflows/docker.yml](./.github/workflows/docker.yml) builds and pushes both images to Docker Hub and GHCR (multi-arch: `linux/amd64` + `linux/arm64`):

| Image | Dockerfile | Tag on `main` | Tag on `v1.2.3` |
|-------|------------|---------------|-----------------|
| `avoinea/sbx-ollama-pi` | `Dockerfile` | `latest`, `sha-<sha>` | `1.2.3`, `1.2`, `sha-<sha>` |
| `avoinea/sbx-ollama-pi` (shell-docker) | `Dockerfile.shell-docker` | `docker`, `docker-sha-<sha>` | `docker-1.2.3`, `docker-1.2`, `docker-sha-<sha>` |

**Required repository secrets** (Settings → Secrets and variables → Actions):

- `DOCKERHUB_USERNAME` — your Docker Hub username
- `DOCKERHUB_TOKEN` — a [Docker Hub access token](https://docs.docker.com/security/for-developers/access-tokens/) (not your password)

GHCR login uses the built-in `GITHUB_TOKEN` — no extra setup needed.

The workflow can also be triggered manually from the Actions tab (`workflow_dispatch`). Builds are cached per Dockerfile via GitHub Actions cache.

## Acknowledgements

This is a fork of [geut/sbx-shell-pi](https://github.com/geut/sbx-shell-pi), originally based on Oleg Šelajev's article [Building custom Docker Sandboxes](https://olegselajev.substack.com/p/building-custom-docker-sandboxes). ~~One key difference: local images never worked for me. `sbx save` completes, but referencing a local image fails. sbx appears to look up the image in a registry instead (you can see this by inspecting `sbx daemon` output).~~
