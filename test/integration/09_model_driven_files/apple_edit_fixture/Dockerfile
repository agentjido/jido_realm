FROM hexpm/elixir@sha256:7fbd282eb30766fef913aaadf114968cdfaccb942636051ba5c301edace82183
RUN apt-get update && apt-get install -y --no-install-recommends ripgrep=13.0.0-4+b2 && rm -rf /var/lib/apt/lists/* \
    && test "$(dpkg-query -W -f='${Version}' bash)" = 5.2.15-2+b13
ENV HEX_HOME=/opt/realm/hex MIX_HOME=/opt/realm/mix MIX_ENV=test MIX_DEPS_PATH=/opt/realm/deps ERL_FLAGS="+S 2:2 +SDio 1 +SDcpu 1"
WORKDIR /opt/realm/setup
COPY mix.exs.seed mix.exs
COPY mix.lock.seed mix.lock
RUN mix local.hex 2.5.1 --force && mix local.rebar --force && mix deps.get --check-locked \
    && MIX_BUILD_PATH=/opt/realm/build mix deps.compile \
    && chmod -R a+rX /opt/realm
COPY acceptance/round_test.exs.seed /opt/realm/acceptance/round_test.exs
ENV HEX_OFFLINE=1
