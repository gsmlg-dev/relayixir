# Relayixir

[![CI](https://github.com/gsmlg-dev/relayixir/actions/workflows/ci.yml/badge.svg)](https://github.com/gsmlg-dev/relayixir/actions/workflows/ci.yml)
[![Test](https://github.com/gsmlg-dev/relayixir/actions/workflows/test.yml/badge.svg)](https://github.com/gsmlg-dev/relayixir/actions/workflows/test.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/relayixir.svg)](https://hex.pm/packages/relayixir)
[![Hex Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/relayixir)

An Elixir-native HTTP/WebSocket reverse proxy built on Bandit + Plug + Mint + Mint.WebSocket.

## Features

- **HTTP Reverse Proxy** — streaming response forwarding with correct chunked/content-length handling
- **WebSocket Proxy** — full bidirectional relay with explicit state machine and close semantics
- **Protocol-Aware Headers** — hop-by-hop stripping, x-forwarded-* injection, configurable host forwarding
- **Telemetry** — structured events for request lifecycle, upstream connections, and WebSocket sessions
- **OTP Supervision** — WebSocket bridges under DynamicSupervisor with temporary restart strategy

## Requirements

- Elixir >= 1.18
- Erlang/OTP >= 27

## Installation

Add `relayixir` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:relayixir, "~> 0.1.0"}
  ]
end
```

## Architecture

Relayixir implements two separate proxy paths:

**HTTP** (request/response):
```
Client → Bandit → Router → HttpPlug → HttpClient (Mint) → Upstream
```

**WebSocket** (bidirectional, long-lived):
```
Client → Bandit → Router → WebSocket.Plug → Bridge (GenServer) → UpstreamClient (Mint.WebSocket) → Upstream
```

See [`docs/design.md`](docs/design.md) for the full architecture document.

## Development

```bash
mix deps.get    # Install dependencies
mix compile     # Compile
mix test        # Run tests
mix format      # Format code
```

## License

MIT
