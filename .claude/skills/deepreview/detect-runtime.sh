#!/usr/bin/env bash
# detect-runtime.sh — emit JSON describing the project's stack(s),
# preferred test command and coverage command. Stack-agnostic best-effort.
set -euo pipefail

ROOT="${1:-$(pwd)}"
cd "$ROOT"

stacks=()
test_cmd=""
coverage_cmd=""

# Helper: assign first wins (don't overwrite already-set commands).
# This lets polyglot repos pick the first detected stack as primary.
set_cmds() {
  test_cmd="${test_cmd:-$1}"
  coverage_cmd="${coverage_cmd:-$2}"
}

# --- Node / TypeScript ---------------------------------------------------
if [[ -f package.json ]]; then
  if [[ -f bun.lockb || -f bun.lock ]]; then
    stacks+=("node:bun"); set_cmds "bun test" "bun test --coverage"
  elif [[ -f pnpm-lock.yaml ]]; then
    stacks+=("node:pnpm"); set_cmds "pnpm test" "pnpm test -- --coverage"
  elif [[ -f yarn.lock ]]; then
    stacks+=("node:yarn"); set_cmds "yarn test" "yarn test --coverage"
  else
    stacks+=("node:npm"); set_cmds "npm test" "npm test -- --coverage"
  fi
fi

# --- Python --------------------------------------------------------------
if [[ -f pyproject.toml ]]; then
  if [[ -f uv.lock ]]; then
    stacks+=("python:uv"); set_cmds "uv run pytest" "uv run pytest --cov"
  elif [[ -f poetry.lock ]]; then
    stacks+=("python:poetry"); set_cmds "poetry run pytest" "poetry run pytest --cov"
  elif [[ -f Pipfile.lock ]]; then
    stacks+=("python:pipenv"); set_cmds "pipenv run pytest" "pipenv run pytest --cov"
  else
    stacks+=("python:pip"); set_cmds "python -m pytest" "python -m pytest --cov"
  fi
elif [[ -f requirements.txt || -f setup.py ]]; then
  stacks+=("python:pip"); set_cmds "python -m pytest" "python -m pytest --cov"
fi

# --- Rust ----------------------------------------------------------------
if [[ -f Cargo.toml ]]; then
  stacks+=("rust:cargo"); test_cmd="${test_cmd:-cargo test}"; coverage_cmd="${coverage_cmd:-cargo llvm-cov --summary-only}"
fi

# --- Go ------------------------------------------------------------------
if [[ -f go.mod ]]; then
  stacks+=("go:go"); test_cmd="${test_cmd:-go test ./...}"; coverage_cmd="${coverage_cmd:-go test -cover ./...}"
fi

# --- Ruby ----------------------------------------------------------------
if [[ -f Gemfile ]]; then
  stacks+=("ruby:bundler")
  if [[ -d spec ]]; then
    test_cmd="${test_cmd:-bundle exec rspec}"
  else
    test_cmd="${test_cmd:-bundle exec rake test}"
  fi
  coverage_cmd="${coverage_cmd:-$test_cmd}"  # simplecov runs inside the test process
fi

# --- JVM -----------------------------------------------------------------
if [[ -f pom.xml ]]; then
  stacks+=("jvm:maven"); test_cmd="${test_cmd:-mvn -q test}"; coverage_cmd="${coverage_cmd:-mvn -q verify}"
elif [[ -f build.gradle || -f build.gradle.kts ]]; then
  stacks+=("jvm:gradle")
  if [[ -x ./gradlew ]]; then
    test_cmd="${test_cmd:-./gradlew test}"; coverage_cmd="${coverage_cmd:-./gradlew test jacocoTestReport}"
  else
    test_cmd="${test_cmd:-gradle test}"; coverage_cmd="${coverage_cmd:-gradle test jacocoTestReport}"
  fi
fi

# --- PHP -----------------------------------------------------------------
if [[ -f composer.json ]]; then
  stacks+=("php:composer")
  if [[ -x vendor/bin/phpunit ]]; then
    test_cmd="${test_cmd:-vendor/bin/phpunit}"
  else
    test_cmd="${test_cmd:-composer test}"
  fi
  coverage_cmd="${coverage_cmd:-$test_cmd --coverage-text}"
fi

# --- Elixir --------------------------------------------------------------
if [[ -f mix.exs ]]; then
  stacks+=("elixir:mix"); test_cmd="${test_cmd:-mix test}"; coverage_cmd="${coverage_cmd:-mix test --cover}"
fi

# --- .NET ----------------------------------------------------------------
if compgen -G "*.sln" > /dev/null || compgen -G "*.csproj" > /dev/null; then
  stacks+=("dotnet:dotnet"); test_cmd="${test_cmd:-dotnet test}"; coverage_cmd="${coverage_cmd:-dotnet test --collect:\"XPlat Code Coverage\"}"
fi

# --- Output --------------------------------------------------------------
# Emit JSON without requiring jq.
{
  printf '{'
  printf '"stacks":['
  for i in "${!stacks[@]}"; do
    [[ $i -gt 0 ]] && printf ','
    printf '"%s"' "${stacks[$i]}"
  done
  printf '],'
  # shell-escape: simple, since none of our commands contain double quotes
  printf '"test_cmd":"%s",' "$test_cmd"
  printf '"coverage_cmd":"%s",' "$coverage_cmd"
  printf '"root":"%s"' "$ROOT"
  printf '}\n'
}
